import 'package:file_selector/file_selector.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'csv_file_source.g.dart';

/// A CSV the user chose, with the file's name for the confirmation dialog.
class PickedCsv {
  const PickedCsv({required this.name, required this.contents});

  final String name;
  final String contents;
}

/// Asks the user for a CSV file.
///
/// A seam, for the same reason `CameraService` and `PasscodeOcr` are: it is the
/// one part of the import that cannot run in a widget test, and everything
/// interesting — parsing, resolution, merging — sits behind it. Tests override
/// the provider with a fake returning canned text, and the whole flow from
/// button tap to written rows is then exercisable on the host.
abstract class CsvFileSource {
  /// Null when the user backs out of the picker.
  Future<PickedCsv?> pick();
}

class FileSelectorCsvSource implements CsvFileSource {
  const FileSelectorCsvSource();

  /// Deliberately broad. A `.csv` arriving from Drive, Downloads or a mail
  /// attachment is reported by Android's document providers under any of these
  /// — and sometimes as `application/octet-stream` — so filtering tightly means
  /// the user's own export shows up greyed out and unselectable. Picking the
  /// wrong file is recoverable and well explained: the parser rejects anything
  /// without the required columns before a single row is written.
  static const XTypeGroup _csv = XTypeGroup(
    label: 'CSV',
    extensions: ['csv', 'txt'],
    mimeTypes: [
      'text/csv',
      'text/plain',
      'text/comma-separated-values',
      'application/csv',
      'application/vnd.ms-excel',
    ],
  );

  @override
  Future<PickedCsv?> pick() async {
    final file = await openFile(acceptedTypeGroups: const [_csv]);
    if (file == null) return null;
    return PickedCsv(name: file.name, contents: await file.readAsString());
  }
}

@riverpod
CsvFileSource csvFileSource(Ref ref) => const FileSelectorCsvSource();
