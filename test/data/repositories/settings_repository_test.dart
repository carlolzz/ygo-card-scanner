import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/repositories/settings_repository.dart';
import 'package:ygo_scanner/models/app_settings.dart';
import 'package:ygo_scanner/models/app_theme_mode.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';

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
  });

  test('save then load round-trips every field', () async {
    await repository.save(
      const AppSettings(
        defaultCondition: CardCondition.lightPlayed,
        defaultEdition: CardEdition.first,
        language: 'DE',
        themeMode: AppThemeMode.light,
      ),
    );

    final settings = await repository.load();

    expect(settings.defaultCondition, CardCondition.lightPlayed);
    expect(settings.defaultEdition, CardEdition.first);
    expect(settings.language, 'DE');
    expect(settings.themeMode, AppThemeMode.light);
  });

  test('save persists enums by name, never by ordinal', () async {
    await repository.save(
      const AppSettings(
        defaultCondition: CardCondition.poor,
        defaultEdition: CardEdition.limited,
        themeMode: AppThemeMode.system,
      ),
    );

    expect(await metaDao.get('settings.default_condition'), 'POOR');
    expect(await metaDao.get('settings.default_edition'), 'LIMITED');
    expect(await metaDao.get('settings.theme_mode'), 'SYSTEM');
  });

  test('an unrecognized stored value falls back to its default', () async {
    // A downgrade past a future enum member, or a hand-edited database.
    // Settings load during app start, so this must not throw.
    await metaDao.set('settings.default_condition', 'PRISTINE');
    await metaDao.set('settings.default_edition', 'SOMETHING_NEW');
    await metaDao.set('settings.theme_mode', 'SEPIA');

    final settings = await repository.load();

    expect(settings.defaultCondition, CardCondition.nearMint);
    expect(settings.defaultEdition, CardEdition.unlimited);
    expect(settings.themeMode, AppThemeMode.dark);
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
