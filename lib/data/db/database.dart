import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

part 'database.g.dart';

@Riverpod(keepAlive: true)
Future<Database> appDatabase(Ref ref) => AppDatabase.instance.database;

/// Opens and owns the app's single SQLite connection.
///
/// The onCreate/onUpgrade/onConfigure callbacks are exposed as static
/// methods so tests can open an in-memory database against the exact same
/// migration code path instead of re-implementing it.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'ygo_scanner.db');
    return openDatabase(
      dbPath,
      version: kSchemaVersion,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
  }

  /// PRAGMA foreign_keys must be set here — pre-transaction — never in
  /// onOpen or inside a transaction, or SQLite silently leaves FK
  /// enforcement off.
  @visibleForTesting
  static Future<void> onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  @visibleForTesting
  static Future<void> onCreate(Database db, int version) async {
    for (var v = 1; v <= version; v++) {
      for (final statement in kMigrations[v]!) {
        await db.execute(statement);
      }
    }
    await db.insert('meta', {'key': 'schema_version', 'value': '$version'});
  }

  @visibleForTesting
  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      for (final statement in kMigrations[v]!) {
        await db.execute(statement);
      }
    }
    await db.update(
      'meta',
      {'value': '$newVersion'},
      where: 'key = ?',
      whereArgs: ['schema_version'],
    );
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
