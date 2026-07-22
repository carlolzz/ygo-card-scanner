import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/db/migrations.dart';

/// Opens a fresh in-memory database through the exact same migration code
/// path the app uses, so tests exercise real onCreate/onUpgrade/onConfigure
/// logic instead of a re-implementation of it.
///
/// `singleInstance: false` matters: sqflite otherwise caches connections by
/// path, and every call here uses the same `inMemoryDatabasePath` — without
/// this, a second call within the same test would silently hand back the
/// first (already-populated) database instead of a genuinely fresh one.
Future<Database> openInMemoryTestDb() {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: kSchemaVersion,
      onConfigure: AppDatabase.onConfigure,
      onCreate: AppDatabase.onCreate,
      onUpgrade: AppDatabase.onUpgrade,
      singleInstance: false,
    ),
  );
}
