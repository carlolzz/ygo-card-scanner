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
/// - The passcode is an *exactly*-eight-digit run. Seven or nine is a misread,
///   not a partial result — we never pad or truncate.
/// - If two spans (or two runs in one span) yield *different* eight-digit
///   values, the frame is ambiguous and we return null; consecutive-frame
///   agreement upstream resolves it.
///
/// Matching works on maximal digit *runs* (`\d+`) rather than stripping every
/// non-digit from a line: on a real card the passcode often sits on the same
/// OCR line as neighbouring text ("46986414 1st Edition"), and cleaning the
/// whole line would count the stray "1" as a ninth digit and reject the frame.
/// A run of exactly eight digits is the passcode; the "1" of "1st" is a
/// separate one-digit run and is ignored. When a span has *no* eight-digit run
/// we fall back to the joined runs — this preserves ML Kit's habit of splitting
/// a passcode across elements ("4698 6414" → two four-digit runs → "46986414")
/// — but only for a span that is digits and whitespace alone (see [_joinable]).
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
  final found = <String>{};
  for (final span in spans) {
    if (roi != null &&
        frameSize != null &&
        frameSize.width > 0 &&
        frameSize.height > 0) {
      final centre = Offset(
        (span.boundingBox.left + span.boundingBox.width / 2) / frameSize.width,
        (span.boundingBox.top + span.boundingBox.height / 2) / frameSize.height,
      );
      if (!roi.contains(centre)) continue;
    }

    final runs =
        RegExp(r'\d+').allMatches(span.text).map((m) => m.group(0)!).toList();
    final eights = runs.where((run) => run.length == 8).toSet();
    if (eights.isNotEmpty) {
      found.addAll(eights);
    } else if (_joinable(span.text)) {
      // No isolated 8-run: try joining space-split digit groups.
      final joined = runs.join();
      if (joined.length == 8) found.add(joined);
    }
  }
  // Exactly one distinct value is a confident read; zero is a miss and more
  // than one is an ambiguous frame — both resolve to null.
  return found.length == 1 ? found.first : null;
}

/// Whether a span's digit runs may be joined into a candidate passcode.
///
/// Only when the span is digits and separating whitespace and nothing else.
/// The fallback exists for ML Kit splitting one printed passcode across
/// elements ("4698 6414"), where the gap is the *only* thing between the runs —
/// but without this guard it also joined a monster's stat line,
/// `ATK/2500  DEF/2100` → `"25002100"`. That is a plausible-looking second
/// distinct value alongside the real passcode, so `found.length == 2` and the
/// whole frame is discarded: passcode mode silently read *nothing* on exactly
/// the monsters most worth logging, whenever ML Kit grouped ATK and DEF onto
/// one line.
bool _joinable(String text) => RegExp(r'^[\d\s]+$').hasMatch(text);

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
