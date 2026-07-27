import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Offset, Rect;

import 'art_frame.dart';
import 'card_detector.dart';
import 'opencv_card_detector.dart';

/// Runs [detectCardSync] on a long-lived background isolate, so the OpenCV work
/// never lands on the UI isolate.
///
/// **Why this exists.** Detection is an edge map, a contour pass, a perspective
/// warp and a second edge pass over the rectified card — tens of milliseconds,
/// three times a second, for as long as the scan screen is open. Run on the UI
/// isolate that is enough to keep Flutter from painting, and a camera preview
/// that stops repainting is indistinguishable from a camera that has died: it
/// is the reported "the preview stayed black" symptom.
///
/// **Why an isolate works here at all.** Nothing crosses the port but plain
/// data. [ArtFrame] is a `Uint8List` plus three ints and [DetectedCard] is that
/// plus a quad and a rect — no OpenCV `Mat`, no native handle, no `Finalizable`.
/// The luma travels as [TransferableTypedData], which moves the buffer rather
/// than copying it. And dartcv4's native bindings are lazily-initialised
/// top-level `final`s, so the worker `dlopen`s the already-loaded library the
/// first time it detects — which is exactly why this is **one long-lived
/// worker** rather than an `Isolate.run` per frame, which would redo that setup
/// three times a second.
///
/// **Degrades, never fails.** If the isolate can't be spawned the detector falls
/// back to running in-process, i.e. to the previous behaviour.
class IsolateCardDetector implements CardDetector {
  IsolateCardDetector();

  final _fallback = const OpenCvCardDetector();

  Isolate? _isolate;
  SendPort? _requests;
  ReceivePort? _responses;
  ReceivePort? _exits;
  ReceivePort? _errors;

  /// Guards the one-shot spawn: several frames can race to the first detection.
  Future<bool>? _starting;

  /// In-flight requests by id, completed as responses come back.
  final Map<int, Completer<DetectedCard?>> _pending = {};
  int _nextId = 0;

  bool _disposed = false;

  @override
  Future<DetectedCard?> detectCard(ArtFrame frame, {Rect? searchRoi}) async {
    if (_disposed) return null;
    if (!await _ensureStarted()) {
      // No worker — run in-process rather than stop detecting altogether.
      return _fallback.detectCard(frame, searchRoi: searchRoi);
    }
    final port = _requests;
    if (port == null) return _fallback.detectCard(frame, searchRoi: searchRoi);

    final id = _nextId++;
    final completer = Completer<DetectedCard?>();
    _pending[id] = completer;
    final startedAt = DateTime.now();
    port.send(<Object?>[
      id,
      TransferableTypedData.fromList([frame.luma]),
      frame.width,
      frame.height,
      frame.rotationDegrees,
      searchRoi?.left,
      searchRoi?.top,
      searchRoi?.right,
      searchRoi?.bottom,
    ]);
    // A response is not guaranteed. If the worker dies or `detectCardSync`
    // wedges, this future would never complete — and the artwork loop awaits it
    // *before* any `yield`, so the whole recognition pipeline stops while the
    // preview keeps painting and the camera health line keeps reading
    // `streaming`. Recognition dead, every on-screen signal green. A timeout
    // turns that into a missed frame, which the pipeline already tolerates.
    return completer.future
        .timeout(
          _requestTimeout,
          onTimeout: () {
            _pending.remove(id);
            _timeouts++;
            // Repeated timeouts mean the worker is gone rather than slow; drop
            // it so the next frame is served in-process instead of waiting out
            // the timeout every time.
            if (_timeouts >= _timeoutsBeforeTeardown) _retireWorker();
            return null;
          },
        )
        .whenComplete(() {
          _lastLatency = DateTime.now().difference(startedAt);
        });
  }

  /// How long a single detection may take before the frame is written off.
  /// Generous next to the ~15-40ms the OpenCV pass actually costs — this is a
  /// liveness check, not a performance budget.
  static const Duration _requestTimeout = Duration(seconds: 2);

  /// Consecutive-ish timeouts tolerated before the worker is presumed dead.
  static const int _timeoutsBeforeTeardown = 3;

  int _timeouts = 0;
  Duration? _lastLatency;

  /// What the detector is doing, for the diagnostics overlay. Detection liveness
  /// had no readout at all, which is what made a wedged worker invisible.
  DetectorHealth get health => DetectorHealth(
    inIsolate: _requests != null,
    lastLatency: _lastLatency,
    timeouts: _timeouts,
  );

  /// Drops a worker presumed dead, leaving [detectCard] on the in-process
  /// fallback. `_starting` is completed and left in place deliberately: a
  /// respawn loop against a worker that dies on every frame would be worse than
  /// detecting in-process.
  void _retireWorker() {
    if (_disposed || _isolate == null && _requests == null) return;
    _teardown();
    _starting = Future<bool>.value(false);
  }

  Future<bool> _ensureStarted() => _starting ??= _spawn();

  Future<bool> _spawn() async {
    final responses = ReceivePort();
    // A worker that exits — for any reason, including a native crash inside
    // OpenCV — must be *noticed*. Without these the port simply goes quiet and
    // every future request waits out its timeout, one frame at a time, forever.
    final exits = ReceivePort()..listen((_) => _retireWorker());
    final errors = ReceivePort()..listen((_) => _retireWorker());
    try {
      _isolate = await Isolate.spawn(
        _detectorWorker,
        responses.sendPort,
        // A detection failure must never take the app down; the worker already
        // returns null on any OpenCV error.
        errorsAreFatal: false,
        onExit: exits.sendPort,
        onError: errors.sendPort,
        debugName: 'card-detector',
      );
    } catch (_) {
      responses.close();
      exits.close();
      errors.close();
      return false;
    }
    _exits = exits;
    _errors = errors;
    _responses = responses;
    // The worker's first message is the port to send requests on.
    final handshake = Completer<SendPort>();
    responses.listen((message) {
      if (message is SendPort) {
        if (!handshake.isCompleted) handshake.complete(message);
        return;
      }
      _onResponse(message);
    });
    // Timed, so a worker that somehow never announces itself degrades to the
    // in-process fallback instead of hanging every frame forever.
    try {
      _requests = await handshake.future.timeout(_handshakeTimeout);
    } on TimeoutException {
      _teardown();
      return false;
    }
    if (_disposed) {
      _teardown();
      return false;
    }
    return true;
  }

  static const Duration _handshakeTimeout = Duration(seconds: 5);

  void _onResponse(Object? message) {
    if (message is! List) return;
    final completer = _pending.remove(message[0] as int);
    if (completer == null) return;
    completer.complete(_decodeResponse(message));
  }

  static DetectedCard? _decodeResponse(List<Object?> message) {
    final luma = message[1] as TransferableTypedData?;
    if (luma == null) return null;
    final quad = message[4] as Float64List;
    final artBox = message[5] as Float64List?;
    return DetectedCard(
      image: ArtFrame(
        luma: luma.materialize().asUint8List(),
        width: message[2] as int,
        height: message[3] as int,
      ),
      quad: [
        for (var i = 0; i < quad.length; i += 2) Offset(quad[i], quad[i + 1]),
      ],
      artBox: artBox == null
          ? null
          : Rect.fromLTRB(artBox[0], artBox[1], artBox[2], artBox[3]),
    );
  }

  /// Releases the worker for good. Any request still in flight resolves to null
  /// — a missed frame, which the pipeline already tolerates.
  void dispose() {
    _disposed = true;
    _teardown();
  }

  /// Drops the worker without retiring the detector, so a spawn that went wrong
  /// leaves [detectCard] falling back in-process rather than returning nothing
  /// forever.
  void _teardown() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _requests = null;
    _responses?.close();
    _responses = null;
    _exits?.close();
    _exits = null;
    _errors?.close();
    _errors = null;
  }
}

/// The worker's entry point: hand back a request port, then detect on demand.
///
/// Top-level, as `Isolate.spawn` requires. It holds no state of its own — every
/// request carries its whole input — so a failure is confined to one frame.
void _detectorWorker(SendPort responses) {
  final requests = ReceivePort();
  responses.send(requests.sendPort);
  requests.listen((message) {
    if (message is! List) return;
    final id = message[0] as int;
    try {
      final luma = (message[1] as TransferableTypedData)
          .materialize()
          .asUint8List();
      final left = message[5] as double?;
      final card = detectCardSync(
        ArtFrame(
          luma: luma,
          width: message[2] as int,
          height: message[3] as int,
          rotationDegrees: message[4] as int,
        ),
        searchRoi: left == null
            ? null
            : Rect.fromLTRB(
                left,
                message[6]! as double,
                message[7]! as double,
                message[8]! as double,
              ),
      );
      responses.send(_encodeResponse(id, card));
    } catch (_) {
      // Same contract as the in-process detector: any failure is a miss.
      responses.send(<Object?>[id, null, 0, 0, null, null]);
    }
  });
}

List<Object?> _encodeResponse(int id, DetectedCard? card) {
  if (card == null) return <Object?>[id, null, 0, 0, null, null];
  final artBox = card.artBox;
  return <Object?>[
    id,
    TransferableTypedData.fromList([card.image.luma]),
    card.image.width,
    card.image.height,
    Float64List.fromList([
      for (final corner in card.quad) ...[corner.dx, corner.dy],
    ]),
    artBox == null
        ? null
        : Float64List.fromList([
            artBox.left,
            artBox.top,
            artBox.right,
            artBox.bottom,
          ]),
  ];
}
