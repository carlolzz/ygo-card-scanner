import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/theme/tokens.dart';
import 'art_frame.dart';

/// Owns the camera and turns its frames into ML-Kit [InputImage]s for the scan
/// pipeline. An abstraction so the state machine can run against a fake source
/// with no hardware in tests — the real implementation is never constructed by
/// tests that override [passcodeReadingsProvider].
abstract class CameraService {
  /// Throttled stream of frames ready for OCR (roughly one per
  /// [ScanTuning.frameInterval]).
  Stream<InputImage> get frames;

  /// The controller backing the live preview: null until [start] has finished
  /// initializing it, and null again once [stop] has released it.
  ///
  /// A [ValueListenable] rather than a plain getter, and that is load-bearing:
  /// `cameraServiceProvider` hands out one long-lived instance and never
  /// publishes a new value, so a widget reading a plain getter would sample it
  /// once — while the camera is still opening — and never learn that the
  /// preview became available.
  ValueListenable<CameraController?> get preview;

  /// The most recent frame reduced to luma, for the artwork-match fallback, or
  /// null before the first frame. Updated in lockstep with [frames].
  ArtFrame? get latestArtFrame;

  /// Opens the back camera and begins streaming frames. Throws (e.g.
  /// [CameraException] on denied permission / no camera) so the pipeline can
  /// surface a camera-error state. Calling twice is a no-op.
  Future<void> start();

  /// Releases the camera (stops streaming, disposes the controller) but leaves
  /// the service reusable — a later [start] brings it back. Safe to call more
  /// than once, including before [start].
  Future<void> stop();

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

  @override
  Stream<InputImage> get frames => _frames.stream;

  @override
  ValueListenable<CameraController?> get preview => _preview;

  @override
  ArtFrame? get latestArtFrame => _latestArtFrame;

  @override
  Future<void> start() => _enqueue(_start);

  Future<void> _start() async {
    if (_disposed || _controller != null) return;
    final cameras = await availableCameras();
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
    // Re-assert continuous auto focus/exposure on every fresh start. These are
    // the defaults, but some devices let autofocus/exposure settle on a stale
    // value under `startImageStream` and only recover on a full camera restart
    // — the "recognition gets easier after re-opening Log Cards" symptom. Best
    // effort: guarded because not every device/mode combination is supported.
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      // Meter on the centre of the frame, where the guide box (and so the
      // card) is. Left to its own devices the camera weights the whole scene,
      // so on a busy or bright desk it focuses and exposes for the surface
      // rather than the card — which is precisely when recognition struggles.
      await controller.setFocusPoint(_meteringPoint);
      await controller.setExposurePoint(_meteringPoint);
    } catch (_) {
      // Unsupported on this device — fall back to the plugin's defaults.
    }
    // Publish before streaming starts: the preview is useful the moment the
    // controller is initialized, and frames only arrive once a card is held
    // up to the lens.
    _preview.value = controller;
    await controller.startImageStream(_onFrame);
  }

  /// Where focus and exposure are metered, in normalized preview coordinates.
  /// The reticle is centred, so this is the card.
  static const Offset _meteringPoint = Offset(0.5, 0.5);

  void _onFrame(CameraImage image) {
    // Time-throttle: OCR is far slower than the camera's frame rate, and the
    // human flipping cards is the real bottleneck (~1 card/sec).
    final now = DateTime.now();
    if (now.difference(_lastEmit) < ScanTuning.frameInterval) return;
    _lastEmit = now;

    final rotation = _rotationDegrees(image);
    if (rotation == null) return;

    // Cache the luma for the artwork-match fallback (defensive copy, so it
    // survives the plugin recycling this frame's buffer).
    final art = _toArtFrame(image, rotation);
    if (art != null) _latestArtFrame = art;

    final input = _toInputImage(image, rotation);
    if (input != null && !_frames.isClosed) _frames.add(input);
  }

  ArtFrame? _toArtFrame(CameraImage image, int rotationDegrees) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final luma = Platform.isAndroid
        ? lumaFromYPlane(plane.bytes, image.width, image.height,
            plane.bytesPerRow)
        : lumaFromBgra(plane.bytes, image.width, image.height,
            plane.bytesPerRow);
    return ArtFrame(
      luma: luma,
      width: image.width,
      height: image.height,
      rotationDegrees: rotationDegrees,
    );
  }

  @override
  Future<void> stop() => _enqueue(_stop);

  Future<void> _stop() async {
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
  Future<void> dispose() => _enqueue(_dispose);

  Future<void> _dispose() async {
    _disposed = true;
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
  /// ML Kit + camera plugin recipe, or null if it can't be determined. Shared by
  /// the OCR ([_toInputImage]) and artwork-match ([_toArtFrame]) paths.
  int? _rotationDegrees(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;
    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) return sensorOrientation % 360;
    final compensation = _orientations[controller.value.deviceOrientation];
    if (compensation == null) return null;
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
