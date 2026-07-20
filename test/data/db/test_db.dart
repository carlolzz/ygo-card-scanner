import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/db/migrations.dart';

/// Opens a fresh in-memory database through the exact same migration code
/// path the app uses, so tests exercise real onCreate/onUpgrade/onConfigure
/// logic instead of a re-implementation of it.
Future<Database> openInMemoryTestDb() {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: kSchemaVersion,
      onConfigure: AppDatabase.onConfigure,
      onCreate: AppDatabase.onCreate,
      onUpgrade: AppDatabase.onUpgrade,
    ),
  );
}
