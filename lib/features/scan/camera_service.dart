import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/theme/tokens.dart';

/// Owns the camera and turns its frames into ML-Kit [InputImage]s for the scan
/// pipeline. An abstraction so the state machine can run against a fake source
/// with no hardware in tests — the real implementation is never constructed by
/// tests that override [passcodeReadingsProvider].
abstract class CameraService {
  /// Throttled stream of frames ready for OCR (roughly one per
  /// [ScanTuning.frameInterval]).
  Stream<InputImage> get frames;

  /// The controller backing the live preview, or null until [start] has
  /// finished initializing it.
  CameraController? get previewController;

  /// Opens the back camera and begins streaming frames. Throws (e.g.
  /// [CameraException] on denied permission / no camera) so the pipeline can
  /// surface a camera-error state. Calling twice is a no-op.
  Future<void> start();

  /// Stops streaming and releases the camera. Safe to call more than once,
  /// including before [start].
  Future<void> stop();
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
  bool _starting = false;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Stream<InputImage> get frames => _frames.stream;

  @override
  CameraController? get previewController => _controller;

  @override
  Future<void> start() async {
    if (_starting || _controller != null) return;
    _starting = true;
    try {
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
      _controller = controller;
      await controller.initialize();
      await controller.startImageStream(_onFrame);
    } finally {
      _starting = false;
    }
  }

  void _onFrame(CameraImage image) {
    // Time-throttle: OCR is far slower than the camera's frame rate, and the
    // human flipping cards is the real bottleneck (~1 card/sec).
    final now = DateTime.now();
    if (now.difference(_lastEmit) < ScanTuning.frameInterval) return;
    _lastEmit = now;

    final input = _toInputImage(image);
    if (input != null && !_frames.isClosed) _frames.add(input);
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
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

  InputImage? _toInputImage(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;
    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else {
      final compensation = _orientations[controller.value.deviceOrientation];
      if (compensation == null) return null;
      final rotated = camera.lensDirection == CameraLensDirection.front
          ? (sensorOrientation + compensation) % 360
          : (sensorOrientation - compensation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(rotated);
    }
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
