import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// A minimal, ML-Kit-agnostic view of one recognized span of text plus where
/// it sits in the frame. Kept free of ML Kit types so [extractPasscode] can be
/// unit-tested offline without constructing plugin objects.
class RecognizedSpan {
  const RecognizedSpan(this.text, this.boundingBox);

  final String text;
  final Rect boundingBox;
}

/// Pulls the single 8-digit passcode out of a frame's recognized text, or
/// returns null when there is no confident match.
///
/// The passcode is (in practice) the only run of exactly eight consecutive
/// digits printed on a Yu-Gi-Oh card, so a strict length check is already
/// highly specific — ATK/DEF, levels, and set codes never reach eight digits.
///
/// Rules, straight from `.claude/skills/scan-pipeline.md`:
/// - A span must clean to *exactly* eight digits. Seven or nine is a misread,
///   not a partial result — we never pad or truncate, so such spans are
///   ignored rather than salvaged.
/// - If two spans yield *different* eight-digit values, the frame is ambiguous
///   and we return null; consecutive-frame agreement upstream resolves it.
///
/// [roi], when supplied together with [frameSize], restricts matching to spans
/// whose centre falls inside a normalized (0..1) rectangle of the frame. It is
/// left off by default in production (see [MlKitPasscodeOcr.read]) because the
/// ML Kit bounding boxes are in the rotated sensor space, and mapping that back
/// to an on-screen "bottom-left" reliably needs real device samples we don't
/// have yet — the same caution the skill raises about premature preprocessing.
String? extractPasscode(
  List<RecognizedSpan> spans, {
  Size? frameSize,
  Rect? roi,
}) {
  String? found;
  for (final span in spans) {
    if (roi != null && frameSize != null && frameSize.width > 0) {
      final centre = Offset(
        (span.boundingBox.left + span.boundingBox.width / 2) / frameSize.width,
        (span.boundingBox.top + span.boundingBox.height / 2) / frameSize.height,
      );
      if (!roi.contains(centre)) continue;
    }

    final digits = span.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) continue;

    if (found != null && found != digits) return null; // ambiguous frame
    found = digits;
  }
  return found;
}

/// Reads a card passcode from a single camera frame. An abstraction so tests
/// can drive the scan state machine with a fake reader and no ML Kit plugin.
abstract class PasscodeOcr {
  /// The 8-digit passcode found in [image], or null if none was read.
  Future<String?> read(InputImage image);

  /// Releases native resources. Safe to call more than once.
  Future<void> close();
}

/// Production [PasscodeOcr] backed by ML Kit on-device text recognition.
class MlKitPasscodeOcr implements PasscodeOcr {
  MlKitPasscodeOcr({TextRecognizer? recognizer})
    : _recognizer = recognizer ?? TextRecognizer();

  final TextRecognizer _recognizer;

  @override
  Future<String?> read(InputImage image) async {
    final recognized = await _recognizer.processImage(image);
    // Match at the line level: ML Kit often splits a passcode's digits across
    // separate elements, but keeps them on one line ("1234 5678"), which
    // cleans to eight digits.
    final spans = <RecognizedSpan>[
      for (final block in recognized.blocks)
        for (final line in block.lines)
          RecognizedSpan(line.text, line.boundingBox),
    ];
    return extractPasscode(spans, frameSize: image.metadata?.size);
  }

  @override
  Future<void> close() => _recognizer.close();
}
