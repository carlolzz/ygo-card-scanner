import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../db/dao/collection_dao.dart';
import '../repositories/collection_repository.dart';
import '../repositories/price_repository.dart';
import 'collection_csv.dart';
import 'collection_value_csv.dart';

part 'collection_exporter.g.dart';

/// Writes the whole collection to a CSV file on device.
///
/// Always exports every entry (`const CollectionFilter()` — no filter), per the
/// standing requirement that export dumps the entire local database, not just
/// the currently filtered/visible view. Delivery is a plain file write to the
/// app documents directory (no share/file-picker dependency); the caller
/// surfaces the returned path to the user.
class CollectionExporter {
  CollectionExporter(this._repository);

  final CollectionRepository _repository;

  Future<String> exportToCsv({DateTime? now}) async {
    final rows = await _repository.getAll(filter: const CollectionFilter());
    final csv = collectionToCsv(rows);

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      p.join(dir.path, 'ygo_collection_${_dateStamp(now ?? DateTime.now())}.csv'),
    );
    await file.writeAsString(csv);
    return file.path;
  }

  /// Writes an already-computed [CollectionValue] as its own CSV.
  ///
  /// The value is **passed in**, not fetched: it has just been calculated and
  /// is on screen, so exporting it needs no [PriceRepository] here, no second
  /// pass over the price cache and — the point — no way for the file to hold
  /// different numbers from the ones the user is looking at.
  ///
  /// A separate file from the collection export, with its own name, because it
  /// is a separate format: it cannot be imported back (see
  /// `collection_value_csv.dart`), and overwriting one with the other would be
  /// a bad surprise.
  Future<String> exportValueToCsv(CollectionValue value, {DateTime? now}) async {
    final csv = collectionValueToCsv(value);

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      p.join(
        dir.path,
        'ygo_collection_value_${_dateStamp(now ?? DateTime.now())}.csv',
      ),
    );
    await file.writeAsString(csv);
    return file.path;
  }

  String _dateStamp(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

@riverpod
Future<CollectionExporter> collectionExporter(Ref ref) async {
  final repository = await ref.watch(collectionRepositoryProvider.future);
  return CollectionExporter(repository);
}
