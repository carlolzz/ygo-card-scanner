import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/export/collection_exporter.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';

import '../db/test_db.dart';

/// Redirects `getApplicationDocumentsDirectory()` to a real temp dir so the
/// exporter can write a file in the test environment.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  late Database testDb;
  late Directory tempDir;

  setUp(() async {
    testDb = await openInMemoryTestDb();
    await seedFakeCollectionIfEmpty(testDb);
    tempDir = await Directory.systemTemp.createTemp('ygo_export_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await testDb.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('exports every collection entry, header included, to a CSV file', () async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) async => testDb)],
    );
    addTearDown(container.dispose);

    final exporter = await container.read(collectionExporterProvider.future);
    final path = await exporter.exportToCsv(now: DateTime(2026, 7, 23));

    expect(path, endsWith('ygo_collection_2026-07-23.csv'));
    final content = await File(path).readAsString();
    final lines =
        content.split('\r\n').where((l) => l.isNotEmpty).toList();

    // Header + one row per seeded entry (6: Mirror Force is seeded twice).
    expect(lines.first, startsWith('passcode,name,'));
    expect(lines, hasLength(7));
    // Every distinct seeded card is present regardless of any UI filter.
    for (final name in [
      'Blue-Eyes White Dragon',
      'Dark Magician',
      'Red-Eyes B. Dragon',
      'Mirror Force',
      'Pot of Greed',
    ]) {
      expect(content, contains(name));
    }
  });
}
