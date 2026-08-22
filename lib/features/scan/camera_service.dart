import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import 'art_frame.dart';

/// Whether the camera's image stream should be considered dead.
///
/// Pure and top-level so the watchdog's one decision is host-testable — the
/// rest of [CameraScanService] needs hardware. [sinceLastFrame] is measured from
/// the last frame's *arrival*, or from the moment streaming started when none
/// has arrived yet.
///
/// A camera that isn't initialized is never "stalled": it is either still
/// opening or already released, and restarting it would fight [start]/[stop].
bool cameraFrameStalled({
  required Duration sinceLastFrame,
  required bool initialized,
}) => initialized && sinceLastFrame > ScanTuning.cameraFrameTimeout;

/// The watchdog's whole decision: should the camera be torn down and reopened?
///
/// Pure and separate from [cameraFrameStalled] — which it wraps rather than
/// replaces — for the reason `card_quad.dart` gives about its own thresholds: a
/// mistake here does not crash, it silently removes the only path back from a
/// dead camera. The `_startWatchdog` timer around it must stay trivial enough
/// that reading it is proof.
///
/// Two situations restart, and the first is the one that used to be missed:
///
/// * **[wantRunning] but no controller.** A `_start` that throws (camera busy,
///   permission revoked mid-session, a CameraX bind failure) has its error
///   swallowed by the serialising queue, so nothing retries it and nothing
///   surfaces an error state either. Before this case existed the watchdog was
///   also *armed* by the tail of a successful `_start`, so a failed one left no
///   watchdog at all: the camera was dead, black and silent for the rest of the
///   process. Frame timing says nothing here — there is no stream to time — so
///   the absence of a controller is the whole signal.
/// * **A controller that has stopped delivering frames**, i.e.
///   [cameraFrameStalled]. [sinceLastFrame] is null before streaming begins,
///   which is not a stall: the camera is still opening.
///
/// [startInFlight] suppresses both, and is not optional: opening a camera takes
/// well over one [ScanTuning.cameraWatchdogInterval], so without it every start
/// would be interrupted by a restart of itself on the very next tick.
///
/// Callers still gate the result on the doubling restart backoff, so a camera
/// that is genuinely gone is not reopened every [ScanTuning.cameraWatchdogInterval]
/// forever.
bool cameraNeedsRestart({
  required bool wantRunning,
  required bool startInFlight,
  required bool hasController,
  required Duration? sinceLastFrame,
  required bool initialized,
}) {
  if (!wantRunning || startInFlight) return false;
  if (!hasController) return true;
  if (sinceLastFrame == null) return false;
  return cameraFrameStalled(
    sinceLastFrame: sinceLastFrame,
    initialized: initialized,
  );
}

/// A snapshot of what the camera is actually doing, for the scan screen's
/// diagnostics readout.
///
/// It exists because "no camera frame yet" used to be shown for four different
/// situations — stream still loading, camera released, passcode mode, and the
/// literal one — which made the single most-reported symptom impossible to
/// diagnose. Each field here answers a different question.
class CameraHealth {
  const CameraHealth({
    required this.initialized,
    required this.streaming,
    required this.framesSeen,
    required this.sinceLastFrame,
    required this.restarts,
    this.droppedFrames = 0,
  });

  /// The controller exists and has finished `initialize()`.
  final bool initialized;

  /// …and `startImageStream` has been called on it.
  final bool streaming;

  /// Frames delivered by the plugin since this service was created (counted on
  /// arrival, before the throttle, so it measures the camera and not us).
  final int framesSeen;

  /// Since the last frame arrived, or since streaming started if none has.
  /// Null before streaming starts.
  final Duration? sinceLastFrame;

  /// How many times the watchdog has restarted a stalled camera.
  final int restarts;

  /// Frames the plugin delivered that could not be converted, and were dropped.
  ///
  /// Its own field because this failure is otherwise *invisible*: the camera is
  /// healthy by every other measure — `streaming`, `framesSeen` rising, the gap
  /// small — while nothing is ever recognised, because the frame never reaches
  /// either cache. The watchdog cannot help (frames genuinely are arriving), so
  /// the readout is the only place it can show up.
  final int droppedFrames;
}

/// One dense line describing [health], for the scan screen's diagnostics box.
///
/// Pure and here rather than in the widget so it can be host-tested: the whole
/// point of this line is that it can be trusted when a user reports what the
/// overlay said.
///
/// Reads as `cam: streaming  f=124  Δ=180ms  r=1  x=3` — state, frames
/// delivered, gap since the last one, watchdog restarts, frames that failed to
/// convert. `r=` and `x=` are omitted while zero (the normal case) so a non-zero
/// value stands out.
String describeCameraHealth(CameraHealth health) {
  final since = health.sinceLastFrame;
  final state = switch (health) {
    _ when !health.streaming => AppStrings.scanDiagnosticsCamOpening,
    _
        when since != null &&
            cameraFrameStalled(
              sinceLastFrame: since,
              initialized: health.initialized,
            ) =>
      AppStrings.scanDiagnosticsCamStalled,
    _ => AppStrings.scanDiagnosticsCamStreaming,
  };
  return [
    state,
    'f=${health.framesSeen}',
    if (since != null) 'Δ=${since.inMilliseconds}ms',
    if (health.restarts > 0) 'r=${health.restarts}',
    if (health.droppedFrames > 0) 'x=${health.droppedFrames}',
  ].join('  ');
}

/// Owns the camera and turns its frames into ML-Kit [InputImage]s for the scan
/// pipeline. An abstraction so the state machine can run against a fake source
/// with no hardware in tests — the real implementation is never constructed by
/// tests that override [passcodeReadingsProvider].
abstract class CameraService {
  /// Throttled stream of frames ready for OCR (roughly one per
  /// [ScanTuning.ocrFrameInterval]), and only while [artCaptureEnabled] is off —
  /// see [latestInputImage].
  ///
  /// Prefer [latestInputImage] + [frameSequence] for anything that does slow
  /// work per frame: this is a broadcast stream, and a broadcast controller
  /// **buffers for a paused subscriber** — which is what an `await for` whose
  /// body awaits actually is. See [latestInputImage].
  Stream<InputImage> get frames;

  /// The most recent frame as an ML-Kit input, or null before the first frame.
  ///
  /// Only maintained while [artCaptureEnabled] is off — i.e. in passcode mode,
  /// the only mode that reads it. The two conversions are mutually exclusive, so
  /// [frameSequence] identifies whichever of this and [latestArtFrame] the live
  /// mode produces, and this one goes stale (not null) in artwork mode.
  ///
  /// Exists so the OCR pipeline can be self-paced like the artwork one: poll
  /// [frameSequence], read this, and a read that overruns the frame interval
  /// simply skips frames instead of growing an unbounded backlog of
  /// progressively staler ones (which would run the agreement and empty-frame
  /// counters over frames from seconds ago).
  InputImage? get latestInputImage;

  /// The controller backing the live preview: null until [start] has finished
  /// initializing it, and null again once [stop] has released it.
  ///
  /// A [ValueListenable] rather than a plain getter, and that is load-bearing:
  /// `cameraServiceProvider` hands out one long-lived instance and never
  /// publishes a new value, so a widget reading a plain getter would sample it
  /// once — while the camera is still opening — and never learn that the
  /// preview became available.
  ValueListenable<CameraController?> get preview;

  /// Whether frames are actually arriving: false until the first one lands after
  /// a [start], and false again from the moment [stop] runs (so a watchdog
  /// restart correctly reads as "opening" while it happens).
  ///
  /// **Not the same as [preview] being non-null**, and the difference is the
  /// point. [start] publishes the controller as soon as `initialize()` returns —
  /// before metering, before `startImageStream` — because the picture is useful
  /// that early. Readiness reported from *that* told the user the camera was
  /// available while nothing had streamed yet. This is the honest signal, and
  /// the one `describeCameraHealth`'s `cam:` line has always used.
  ///
  /// A [ValueListenable] for the same load-bearing reason as [preview]: the
  /// service instance is handed out once and never republished, so a widget
  /// sampling a getter would latch whatever was true when it first built.
  ValueListenable<bool> get streaming;

  /// The most recent frame reduced to luma, for artwork recognition, or null
  /// before the first frame. Only maintained while [artCaptureEnabled] is on.
  ArtFrame? get latestArtFrame;

  /// Monotonic counter incremented every time a frame is delivered — i.e. every
  /// time [latestArtFrame] or [latestInputImage] is replaced.
  ///
  /// The artwork pipeline polls this instead of subscribing to [frames]: it
  /// always works on the newest frame, and comparing the sequence guarantees it
  /// never hashes the same physical frame twice (which would double-count the
  /// controller's frame-agreement run) and never builds a backlog when a
  /// detection pass runs long.
  int get frameSequence;

  /// What the camera is doing right now, for the diagnostics readout.
  CameraHealth get health;

  /// Which pipeline the camera is feeding: [latestArtFrame] when on,
  /// [latestInputImage]/[frames] when off. Turned off in passcode mode, where
  /// the artwork pipeline never reads a frame — and each conversion is a
  /// full-frame copy (~1 MB/s at this cadence), so building the one nothing
  /// consumes is pure allocation.
  ///
  /// Also selects the throttle: [ScanTuning.artFrameInterval] when on,
  /// [ScanTuning.ocrFrameInterval] when off.
  set artCaptureEnabled(bool enabled);

  /// Whether an arriving frame should be converted at all.
  ///
  /// The camera now outlives the scan screen — it opens once and stays open for
  /// the whole foreground — so there are long stretches with a live stream and
  /// nobody reading it. Each conversion is a full-frame copy (~1 MB/s at
  /// [ScanTuning.artFrameInterval]), and doing it for a cache nothing polls is
  /// pure waste. Owned by `ScanController`, which is the thing whose lifetime
  /// actually means "a screen is scanning".
  ///
  /// Frame *arrival* bookkeeping still runs while this is off, so the watchdog
  /// keeps measuring the camera rather than our own gating.
  set frameProcessingEnabled(bool enabled);

  /// Applies an exposure compensation of [ev] stops, clamped to what the device
  /// supports. Zero restores the metered exposure.
  ///
  /// Exists for foil glare, which is *specular*: the camera meters for the
  /// average scene, an Ultra/Secret rare returns a mirror highlight, and the
  /// artwork under it clips to white — destroying exactly the structure the
  /// perceptual hash is computed from. Stopping down recovers it.
  ///
  /// Best-effort, like the metering calls: a device that refuses is left on its
  /// own defaults rather than failing the scan. See `nextExposureOffset` for the
  /// (pure, tested) decision of *when* to call this.
  Future<void> setExposureCompensation(double ev);

  /// Opens the back camera and begins streaming frames. Throws (e.g.
  /// [CameraException] on denied permission / no camera) so the pipeline can
  /// surface a camera-error state. Calling twice is a no-op.
  Future<void> start();

  /// Releases the camera (stops streaming, disposes the controller) but leaves
  /// the service reusable — a later [start] brings it back. Safe to call more
  /// than once, including before [start].
  Future<void> stop();

  /// Releases and immediately reopens the camera.
  ///
  /// The user-facing counterpart to the watchdog, and it exists because one
  /// failure mode is undetectable from Dart: `camera_android_camerax` can black
  /// out the *preview surface* while the analysis stream keeps delivering
  /// (flutter/flutter#27688). Every signal the app has says healthy — frames
  /// arriving, recognition working — and the screen is black. Until now the only
  /// remedy documented anywhere was "close the app fully and reopen".
  Future<void> restart();

  /// Permanently tears the service down: releases the camera *and* closes the
  /// frame stream. Called once, when the owning provider disposes. A stopped
  /// service can be restarted; a disposed one cannot.
  Future<void> dispose();
}

/// Production [CameraService] backed by the `camera` plugin.
///
/// The constructor does no platform work — all hardware access happens in
/// [start] — so simply reading the provider in a test (without starting it) is
/// harmless.
class CameraScanService implements CameraService {
  final StreamController<InputImage> _frames =
      StreamController<InputImage>.broadcast();
  CameraController? _controller;
  bool _disposed = false;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  ArtFrame? _latestArtFrame;
  InputImage? _latestInputImage;
  int _frameSequence = 0;
  bool _artCaptureEnabled = true;
  bool _frameProcessingEnabled = false;

  /// Whether the camera is *meant* to be running: set by [start], cleared by
  /// [stop]. Two things depend on it, and both used to be broken without it.
  ///
  /// [_start] consults it, so a restart enqueued by the watchdog can no longer
  /// undo a [stop] that landed between the restart's `_stop` and its `_start` —
  /// which reopened the camera while the app was backgrounded.
  ///
  /// And the watchdog consults it (via [cameraNeedsRestart]) to tell "no
  /// controller because we were asked to release it" from "no controller because
  /// opening it failed", which is what makes recovering from the latter possible
  /// at all.
  bool _wantRunning = false;

  /// True for the duration of a [_start]. The watchdog stands down while it is
  /// set — opening a camera takes far longer than one watchdog interval, so a
  /// start would otherwise be aborted by a restart of itself.
  bool _startInFlight = false;

  /// Frame *arrival* bookkeeping, which is what the watchdog judges — distinct
  /// from [_lastEmit], the throttle's own clock.
  int _framesSeen = 0;
  int _droppedFrames = 0;
  DateTime? _lastFrameAt;
  DateTime? _streamingSince;

  Timer? _watchdog;
  int _restarts = 0;
  Duration _restartBackoff = ScanTuning.cameraWatchdogInterval;
  DateTime? _lastRestartAt;

  /// All start/stop/dispose work is chained onto this queue so the operations
  /// can never interleave. Without it, the OS permission dialog (which pauses
  /// the app mid-[start], firing a [stop]) could leave a half-opened controller
  /// or a start blocked behind another start — the "must leave and re-enter the
  /// screen" bug. The queue continues past a failed op (denied permission)
  /// while still surfacing that error to the caller.
  Future<void> _queue = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Never disposed on purpose: [stop] can run while the preview widget is
  /// still listening (the lifecycle observer stops the camera before the widget
  /// tree unmounts), and a disposed [ValueNotifier] throws when that listener
  /// detaches. The notifier dies with the service instance.
  final ValueNotifier<CameraController?> _preview =
      ValueNotifier<CameraController?>(null);

  /// Never disposed, for exactly the reason [_preview] is not.
  final ValueNotifier<bool> _streaming = ValueNotifier<bool>(false);

  @override
  Stream<InputImage> get frames => _frames.stream;

  @override
  ValueListenable<CameraController?> get preview => _preview;

  @override
  ValueListenable<bool> get streaming => _streaming;

  @override
  ArtFrame? get latestArtFrame => _latestArtFrame;

  @override
  InputImage? get latestInputImage => _latestInputImage;

  @override
  int get frameSequence => _frameSequence;

  @override
  set artCaptureEnabled(bool enabled) => _artCaptureEnabled = enabled;

  @override
  set frameProcessingEnabled(bool enabled) => _frameProcessingEnabled = enabled;

  @override
  CameraHealth get health {
    final controller = _controller;
    final reference = _lastFrameAt ?? _streamingSince;
    return CameraHealth(
      initialized: controller?.value.isInitialized ?? false,
      streaming: _streamingSince != null,
      framesSeen: _framesSeen,
      sinceLastFrame: reference == null
          ? null
          : DateTime.now().difference(reference),
      restarts: _restarts,
      droppedFrames: _droppedFrames,
    );
  }

  @override
  Future<void> start() {
    // Set *before* enqueuing, not inside [_start]: the flag says what the app
    // wants, and it has to be true by the time the watchdog below first ticks —
    // which can be long before a queued `_start` gets its turn.
    _wantRunning = true;
    // Armed here rather than at the tail of a successful [_start], which is the
    // fix for the worst version of this bug: a `_start` that threw left no
    // watchdog behind, so nothing ever retried and the camera stayed black for
    // the rest of the process. Restarting it is now the watchdog's job in both
    // senses — stalled *and* never-opened.
    _startWatchdog();
    return _enqueue(_start);
  }

  @override
  Future<void> restart() {
    _wantRunning = true;
    // A user-initiated restart is not a backoff attempt: it is the answer to a
    // symptom the watchdog cannot see, so it must never be delayed or skipped by
    // the automatic path's rate limiting, and it must leave that limiting reset
    // for whatever comes next.
    _restartBackoff = ScanTuning.cameraWatchdogInterval;
    _lastRestartAt = null;
    _startWatchdog();
    _enqueue(_stop);
    return _enqueue(_start);
  }

  /// The device's camera list, resolved once per process.
  ///
  /// `availableCameras()` is a platform round-trip that enumerates and opens
  /// characteristics for every camera, and the answer cannot change while the
  /// app runs — but it was being paid on every scan-screen entry, every resume
  /// from background, and every watchdog restart, in front of the already-slow
  /// `initialize()`. The **resolved list** is cached rather than the future, so
  /// a failure (no permission yet, camera service temporarily unavailable)
  /// leaves this null and the next [start] genuinely retries instead of
  /// replaying a cached error forever.
  static List<CameraDescription>? _cachedCameras;

  Future<void> _start() async {
    // `!_wantRunning` is the guard that stops a watchdog restart from undoing a
    // [stop] that landed between the restart's `_stop` and its `_start` — which
    // reopened the camera while the app was backgrounded.
    if (_disposed || !_wantRunning || _controller != null) return;
    _startInFlight = true;
    try {
      await _openCamera();
    } finally {
      // In a `finally` so a throw (denied permission, camera busy, a CameraX
      // bind failure) still hands the watchdog back its job. That is the whole
      // recovery path: the error itself is swallowed by the queue.
      _startInFlight = false;
    }
  }

  Future<void> _openCamera() async {
    // No race: [_enqueue] serialises every start against every other start.
    final cameras = _cachedCameras ??= await availableCameras();
    if (cameras.isEmpty) {
      throw CameraException('noCamera', 'No camera available on this device.');
    }
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      // A single-plane NV21 (Android) / BGRA (iOS) frame is what the ML Kit
      // InputImage conversion below expects.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    // `initialize()` is where Android first prompts for the CAMERA permission,
    // so the app can be disposed out from under us while it awaits. The queue
    // guarantees no [stop] runs concurrently, but a [dispose] flips [_disposed]
    // — so re-check afterwards and release this orphan controller if so.
    await controller.initialize();
    if (_disposed) {
      await controller.dispose();
      return;
    }
    _controller = controller;
    // Publish immediately — before metering, before streaming. The preview is
    // useful the moment the controller is initialized, and everything after
    // this line is either best-effort or only matters once a card is held up to
    // the lens. Metering used to sit in front of it, putting four awaited
    // platform round-trips between `initialize()` and the first visible frame
    // for no benefit: the picture does not depend on them.
    _preview.value = controller;
    // Re-assert continuous auto focus/exposure on every fresh start. These are
    // the defaults, but some devices let autofocus/exposure settle on a stale
    // value under `startImageStream` and only recover on a full camera restart
    // — the "recognition gets easier after re-opening Log Cards" symptom.
    await _meter(controller);
    await controller.startImageStream(_onFrame);
    // …and meter again afterwards. Binding CameraX's image-analysis use case
    // rebinds the camera, which cancels any focus-and-metering action already
    // running — so a point set before the stream started may never take effect.
    await _meter(controller);
    _streamingSince = DateTime.now();
    _lastFrameAt = null;
    // `streaming` deliberately stays false until a frame actually *arrives* —
    // see [CameraService.streaming]. `startImageStream` returning proves only
    // that CameraX accepted the binding.
  }

  /// Points focus and exposure at the centre of the frame, where the guide box
  /// (and so the card) is. Left to its own devices the camera weights the whole
  /// scene, so on a busy or bright desk it focuses and exposes for the surface
  /// rather than the card — precisely when recognition struggles.
  ///
  /// Each call is guarded **individually**: these are four independent
  /// best-effort settings, and one shared `try` meant a throw from the first
  /// silently skipped the rest. Not hypothetical —
  /// `camera_android_camerax` 0.7.4+1's changelog is a fix for `setFocusMode`
  /// throwing when there are no auto-focus points, which on every affected
  /// device would have taken the metering points down with it.
  Future<void> _meter(CameraController controller) async {
    await _tryCamera(() => controller.setFocusMode(FocusMode.auto));
    await _tryCamera(() => controller.setExposureMode(ExposureMode.auto));
    await _tryCamera(() => controller.setFocusPoint(_meteringPoint));
    await _tryCamera(() => controller.setExposurePoint(_meteringPoint));
  }

  @override
  Future<void> setExposureCompensation(double ev) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await _tryCamera(() async {
      // The supported range is device-specific and the plugin *throws* outside
      // it, so clamping is required rather than defensive. Querying each time
      // costs two cheap platform reads and avoids caching a range across the
      // camera swaps this service already handles.
      final min = await controller.getMinExposureOffset();
      final max = await controller.getMaxExposureOffset();
      await controller.setExposureOffset(ev.clamp(min, max));
    });
  }

  /// Runs a best-effort camera call, swallowing "unsupported on this device".
  static Future<void> _tryCamera(Future<void> Function() op) async {
    try {
      await op();
    } catch (_) {
      // Unsupported on this device — fall back to the plugin's defaults.
    }
  }

  /// Where focus and exposure are metered, in normalized preview coordinates:
  /// the centre of the guide box, which is where the card is.
  ///
  /// The box is no longer at the viewport's centre — it sits
  /// [ScanReticleTokens.verticalOffsetFraction] below it, to leave a readable
  /// band above — so this follows it rather than staying at 0.5. The
  /// correspondence is exact only where the preview's vertical axis maps 1:1
  /// through the cover crop (the usual tall-phone-versus-4:3-sensor case); on
  /// other pairings it is off by the crop factor, which is well inside any
  /// device's metering region. Unverifiable on host, like everything else that
  /// talks to the camera.
  static const Offset _meteringPoint = Offset(
    0.5,
    0.5 + ScanReticleTokens.verticalOffsetFraction,
  );

  void _onFrame(CameraImage image) {
    // Record *arrival* first, unconditionally: this is what the watchdog judges,
    // so it must reflect the camera rather than our own throttling or a
    // conversion that fails below. (It used to sit after the throttle
    // assignment, so a frame we dropped still consumed the throttle window.)
    final now = DateTime.now();
    _framesSeen++;
    _lastFrameAt = now;
    // A delivered frame proves the camera is alive, so spend any restart backoff.
    _restartBackoff = ScanTuning.cameraWatchdogInterval;
    // …and it is the only thing that does, which is why readiness is published
    // from here and not from `startImageStream` returning.
    if (!_streaming.value) _streaming.value = true;

    // Nothing is scanning: the camera stays open across screens now, and a
    // conversion for a cache nobody polls is a full-frame copy thrown away. The
    // arrival bookkeeping above still runs, so the watchdog keeps measuring the
    // camera rather than this gate.
    if (!_frameProcessingEnabled) return;

    // Time-throttle: recognition is far slower than the camera's frame rate,
    // and the human flipping cards is the real bottleneck (~1 card/sec).
    //
    // The interval depends on which pipeline is live, and one clock is enough
    // because the two are mutually exclusive: [artCaptureEnabled] is false
    // exactly in passcode mode, and `passcodeReadings` is inert outside it. The
    // artwork path wants the faster cadence (it is the primary path, and its
    // latency is dominated by waiting for agreeing frames); the OCR path
    // deliberately keeps the slower one. Sharing `_lastEmit` across a mode
    // switch only means the first frame after it can be up to one interval late.
    final wantArt = _artCaptureEnabled;
    final interval = wantArt
        ? ScanTuning.artFrameInterval
        : ScanTuning.ocrFrameInterval;
    if (now.difference(_lastEmit) < interval) return;

    final rotation = _rotationDegrees(image);
    if (rotation == null) {
      _droppedFrames++;
      return;
    }

    // Conversion is the one thing here that can throw on an unexpected buffer
    // layout (`lumaFromYPlane` indexes by `bytesPerRow`), and a throw inside a
    // plugin callback takes the *rest* of this method with it — so a surprise in
    // one path would silently cost the other its frame too. Convert first,
    // commit after.
    ArtFrame? art;
    InputImage? input;
    try {
      // Exactly one conversion runs, for whichever pipeline is live. Both are
      // real per-frame copies — the luma plane for artwork, a concatenation of
      // all planes for ML Kit — so building the one nothing reads is pure
      // allocation, around a megabyte a second at this cadence. That was
      // already true of the luma copy in passcode mode; it is now equally true
      // of the ML Kit input in artwork mode, which matters more since artwork
      // mode runs at twice the rate.
      if (wantArt) {
        art = _toArtFrame(image, rotation);
      } else {
        input = _toInputImage(image, rotation);
      }
    } catch (_) {
      // A malformed frame is not fatal and not actionable: drop it *without*
      // spending the throttle window, so the next frame is tried immediately
      // rather than a whole interval later. Counted, though — a frame layout
      // this never accepts is otherwise indistinguishable from a healthy camera
      // that simply never sees a card.
      _droppedFrames++;
      return;
    }
    if (art == null && input == null) {
      _droppedFrames++;
      return;
    }

    // Only a frame we actually delivered consumes the throttle window.
    _lastEmit = now;
    if (art != null) _latestArtFrame = art;
    if (input != null) {
      _latestInputImage = input;
      if (!_frames.isClosed) _frames.add(input);
    }
    // One sequence for both caches, so a poller can tell "new frame" from
    // "same frame" regardless of which pipeline it drives.
    _frameSequence++;
  }

  // ---------------------------------------------------------------------------
  // Watchdog.
  // ---------------------------------------------------------------------------

  /// Watches for the camera dying and reopens it when it does.
  ///
  /// Partly a mitigation for `camera_android_camerax`, whose analyzer stops
  /// delivering frames at random (flutter/flutter#152763) and whose preview can
  /// black out under `startImageStream` (flutter/flutter#27688) — both of which
  /// reach the user as "the camera is bugged" or a permanent
  /// "no camera frame yet". Neither is fixable from Dart; noticing is.
  ///
  /// And partly this app's own recovery path: **armed by [start], not by the end
  /// of a successful [_start]**. That ordering is the whole point. A `_start`
  /// that throws has its error swallowed by [_enqueue]'s chain, so it surfaces
  /// nowhere — and while the watchdog was armed at the tail of `_start`, a
  /// throw meant no watchdog was ever created, nothing retried, and the camera
  /// stayed black and silent for the rest of the process with every on-screen
  /// signal green.
  ///
  /// The restart goes through [_enqueue], so it can never interleave with a real
  /// [start]/[stop] (the lifecycle listener's, say).
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(ScanTuning.cameraWatchdogInterval, (_) {
      final snapshot = health;
      if (!cameraNeedsRestart(
        wantRunning: _wantRunning,
        startInFlight: _startInFlight,
        hasController: _controller != null,
        sinceLastFrame: snapshot.sinceLastFrame,
        initialized: snapshot.initialized,
      )) {
        return;
      }
      // Back off between attempts: a camera that is genuinely dead rather than
      // merely stalled must not be restarted every two seconds forever, since
      // each restart blinks the preview.
      final last = _lastRestartAt;
      if (last != null && DateTime.now().difference(last) < _restartBackoff) {
        return;
      }
      _restart();
    });
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  void _restart() {
    _lastRestartAt = DateTime.now();
    _restarts++;
    final doubled = _restartBackoff * 2;
    _restartBackoff = doubled > ScanTuning.cameraRestartMaxBackoff
        ? ScanTuning.cameraRestartMaxBackoff
        : doubled;
    // Deliberately not awaited: a timer callback must not block, and the queue
    // serialises these against anything else start/stop.
    _enqueue(_stop);
    _enqueue(_start);
  }

  ArtFrame? _toArtFrame(CameraImage image, int rotationDegrees) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final luma = Platform.isAndroid
        ? lumaFromYPlane(
            plane.bytes,
            image.width,
            image.height,
            plane.bytesPerRow,
          )
        : lumaFromBgra(
            plane.bytes,
            image.width,
            image.height,
            plane.bytesPerRow,
          );
    return ArtFrame(
      luma: luma,
      width: image.width,
      height: image.height,
      rotationDegrees: rotationDegrees,
    );
  }

  @override
  Future<void> stop() {
    // Cleared here rather than inside [_stop], which is also the first half of
    // every restart: this is the one call that means "the app no longer wants a
    // camera", and it is what [_start] and the watchdog both consult.
    _wantRunning = false;
    _stopWatchdog();
    return _enqueue(_stop);
  }

  Future<void> _stop() async {
    _streamingSince = null;
    _lastFrameAt = null;
    _streaming.value = false;
    final controller = _controller;
    _controller = null;
    // Retract the preview *before* disposing, so nothing can paint a disposed
    // controller.
    _preview.value = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {
        // Already stopped / disposed — nothing to release.
      }
      await controller.dispose();
    }
    // Deliberately does NOT close [_frames]: the service must survive a
    // stop()/start() cycle (backgrounding, the permission dialog). The stream
    // is closed only in [dispose].
  }

  @override
  Future<void> dispose() {
    // Both flags immediately, not just inside the queued [_dispose]: the queue
    // may be several awaited platform round-trips deep, and nothing should be
    // restarted on the way there.
    _wantRunning = false;
    _stopWatchdog();
    return _enqueue(_dispose);
  }

  Future<void> _dispose() async {
    _disposed = true;
    _wantRunning = false;
    _stopWatchdog();
    await _stop();
    if (!_frames.isClosed) await _frames.close();
  }

  /// Maps orientation compensation for the rear camera, per the ML Kit +
  /// camera plugin reference recipe.
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// The clockwise rotation (degrees) needed to make [image] upright, per the
  /// ML Kit + camera plugin recipe. Null only when there is no controller (a
  /// frame still in flight from a camera we have just released). Shared by the
  /// OCR ([_toInputImage]) and artwork-match ([_toArtFrame]) paths.
  ///
  /// An unmapped `deviceOrientation` falls back to the bare sensor orientation
  /// rather than dropping the frame: a dropped frame is invisible from the
  /// outside and presents as a permanent "no card detected" / "no camera frame",
  /// whereas the portrait compensation is 0 anyway on the orientation this app
  /// is used in.
  int? _rotationDegrees(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;
    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) return sensorOrientation % 360;
    final compensation = _orientations[controller.value.deviceOrientation] ?? 0;
    return camera.lensDirection == CameraLensDirection.front
        ? (sensorOrientation + compensation) % 360
        : (sensorOrientation - compensation + 360) % 360;
  }

  InputImage? _toInputImage(CameraImage image, int rotationDegrees) {
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    // The nv21 / bgra8888 request above yields exactly one plane.
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
