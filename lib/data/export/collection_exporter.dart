import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../db/dao/collection_dao.dart';
import '../repositories/collection_repository.dart';
import 'collection_csv.dart';

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
