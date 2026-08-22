import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

part 'file_share.g.dart';

/// What became of a share sheet.
///
/// Our own enum rather than `share_plus`'s `ShareResultStatus`, so that package
/// stays behind this seam and out of the widget layer — the same reason
/// [PickedCsv] wraps an `XFile`.
enum ShareOutcome {
  /// The user picked a target. On Android this means the chooser reported a
  /// component, which is as close to "it arrived" as the platform gets.
  shared,

  /// The user backed out of the sheet without choosing anything.
  cancelled,

  /// The platform could not tell us either way. Treated as [shared] by callers,
  /// deliberately: reporting a cancellation that may not have happened is worse
  /// than reporting a success that may not have happened, because the file *was*
  /// written and the sheet *was* offered.
  unknown,
}

/// Hands files to the OS share sheet.
///
/// A seam, for the same reason [CsvFileSource], `CameraService` and
/// `PasscodeOcr` are: the share sheet is the one part of an export that cannot
/// run in a widget test, and what sits on either side of it — deciding what to
/// tell the user afterwards — is exactly what was wrong. Every call site used to
/// choose its SnackBar text *before* the sheet opened and then discard the
/// result, so backing out of the sheet still reported
/// "Exported — choose where to save it." about a file left in the
/// app-documents directory, which on Android the user cannot browse to.
abstract class FileShare {
  /// Empty [paths] is not a valid call — callers have nothing to share and
  /// should not have got here.
  Future<ShareOutcome> shareFiles(List<String> paths, {String? subject});
}

class SharePlusFileShare implements FileShare {
  const SharePlusFileShare();

  @override
  Future<ShareOutcome> shareFiles(List<String> paths, {String? subject}) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [for (final path in paths) XFile(path)],
        subject: subject,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => ShareOutcome.shared,
      ShareResultStatus.dismissed => ShareOutcome.cancelled,
      ShareResultStatus.unavailable => ShareOutcome.unknown,
    };
  }
}

@riverpod
FileShare fileShare(Ref ref) => const SharePlusFileShare();
