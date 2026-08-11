import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/repositories/settings_repository.dart';
import 'package:ygo_scanner/models/app_settings.dart';
import 'package:ygo_scanner/models/app_theme_mode.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/collection_view_mode.dart';

import '../db/test_db.dart';

void main() {
  late Database db;
  late MetaDao metaDao;
  late SettingsRepository repository;

  setUp(() async {
    db = await openInMemoryTestDb();
    metaDao = MetaDao(db);
    repository = SettingsRepository(metaDao);
  });

  tearDown(() async {
    await db.close();
  });

  test('load returns the defaults on a database with no settings', () async {
    final settings = await repository.load();

    expect(settings.defaultCondition, CardCondition.nearMint);
    expect(settings.defaultEdition, CardEdition.unlimited);
    expect(settings.language, 'EN');
    expect(settings.themeMode, AppThemeMode.dark);
    expect(settings.showScanDiagnostics, isFalse);
    expect(settings.showScanHelp, isTrue);
    expect(settings.confirmBeforeDelete, isTrue);
    expect(settings.collectionViewMode, CollectionViewMode.standard);
    // No preference is the default: most collections are mixed, and a wrong
    // preselection fills a field the user then has no reason to re-check.
    expect(settings.defaultRarity, isNull);
  });

  test('save then load round-trips every field', () async {
    await repository.save(
      const AppSettings(
        defaultCondition: CardCondition.lightPlayed,
        defaultEdition: CardEdition.first,
        language: 'DE',
        defaultRarity: 'Secret Rare',
        themeMode: AppThemeMode.light,
        showScanDiagnostics: true,
        showScanHelp: false,
        confirmBeforeDelete: false,
        collectionViewMode: CollectionViewMode.minifyFull,
      ),
    );

    final settings = await repository.load();

    expect(settings.defaultCondition, CardCondition.lightPlayed);
    expect(settings.defaultEdition, CardEdition.first);
    expect(settings.language, 'DE');
    expect(settings.defaultRarity, 'Secret Rare');
    expect(settings.themeMode, AppThemeMode.light);
    expect(settings.showScanDiagnostics, isTrue);
    expect(settings.showScanHelp, isFalse);
    expect(settings.confirmBeforeDelete, isFalse);
    expect(settings.collectionViewMode, CollectionViewMode.minifyFull);
  });

  // `MetaDao` is a get/set pair with no delete, so "no preference" has to be
  // storable rather than absent — clearing the setting writes an empty string,
  // and it has to read back as null or the preference could never be turned off.
  test('clearing the rarity preference round-trips as no preference', () async {
    await repository.save(const AppSettings(defaultRarity: 'Common'));
    expect((await repository.load()).defaultRarity, 'Common');

    await repository.save(const AppSettings());
    expect((await repository.load()).defaultRarity, isNull);
    expect(await metaDao.get('settings.default_rarity'), '');
  });

  test('a blank stored rarity reads as no preference', () async {
    // A hand-edited value of pure whitespace would otherwise become a rarity
    // that matches nothing, which looks exactly like the feature being broken.
    await metaDao.set('settings.default_rarity', '   ');
    expect((await repository.load()).defaultRarity, isNull);
  });

  test('a malformed boolean falls back to its default', () async {
    await metaDao.set('settings.show_scan_diagnostics', 'yes');
    await metaDao.set('settings.show_scan_help', '1');
    await metaDao.set('settings.confirm_before_delete', '');

    final settings = await repository.load();

    expect(settings.showScanDiagnostics, isFalse);
    expect(settings.showScanHelp, isTrue);
    expect(settings.confirmBeforeDelete, isTrue);
  });

  test('save persists enums by name, never by ordinal', () async {
    await repository.save(
      const AppSettings(
        defaultCondition: CardCondition.poor,
        defaultEdition: CardEdition.limited,
        themeMode: AppThemeMode.system,
        collectionViewMode: CollectionViewMode.minifyStandard,
      ),
    );

    expect(await metaDao.get('settings.default_condition'), 'POOR');
    expect(await metaDao.get('settings.default_edition'), 'LIMITED');
    expect(await metaDao.get('settings.theme_mode'), 'SYSTEM');
    expect(
      await metaDao.get('settings.collection_view_mode'),
      'MINIFY_STANDARD',
    );
  });

  test('an unrecognized stored value falls back to its default', () async {
    // A downgrade past a future enum member, or a hand-edited database.
    // Settings load during app start, so this must not throw.
    await metaDao.set('settings.default_condition', 'PRISTINE');
    await metaDao.set('settings.default_edition', 'SOMETHING_NEW');
    await metaDao.set('settings.theme_mode', 'SEPIA');
    await metaDao.set('settings.collection_view_mode', 'TINY');

    final settings = await repository.load();

    expect(settings.defaultCondition, CardCondition.nearMint);
    expect(settings.defaultEdition, CardEdition.unlimited);
    expect(settings.themeMode, AppThemeMode.dark);
    expect(settings.collectionViewMode, CollectionViewMode.standard);
  });

  test('one bad value does not discard the others', () async {
    await repository.save(
      const AppSettings(
        defaultCondition: CardCondition.mint,
        language: 'JP',
        themeMode: AppThemeMode.light,
      ),
    );
    await metaDao.set('settings.default_edition', 'NONSENSE');

    final settings = await repository.load();

    expect(settings.defaultCondition, CardCondition.mint);
    expect(settings.language, 'JP');
    expect(settings.themeMode, AppThemeMode.light);
    expect(settings.defaultEdition, CardEdition.unlimited);
  });
}
