import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/repositories/settings_repository.dart';
import 'package:ygo_scanner/models/app_language.dart';
import 'package:ygo_scanner/models/app_settings.dart';
import 'package:ygo_scanner/models/app_theme_mode.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/collection_sort_by.dart';
import 'package:ygo_scanner/models/collection_view_mode.dart';
import 'package:ygo_scanner/models/fast_log_field.dart';

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
    // English, so an existing install reads exactly as it did before.
    expect(settings.appLanguage, AppLanguage.english);
    expect(settings.showScanDiagnostics, isFalse);
    expect(settings.showScanHelp, isTrue);
    expect(settings.keepCameraReady, isTrue);
    expect(settings.confirmBeforeDelete, isTrue);
    expect(settings.collectionViewMode, CollectionViewMode.minifyStandard);
    expect(settings.collectionSortBy, CollectionSortBy.name);
    expect(settings.collectionSortDescending, isFalse);
    expect(settings.fastLogEnabled, isFalse);
    expect(settings.fastLogFields, isEmpty);
  });

  test('save then load round-trips every field', () async {
    await repository.save(
      const AppSettings(
        defaultCondition: CardCondition.lightPlayed,
        defaultEdition: CardEdition.first,
        language: 'DE',
        themeMode: AppThemeMode.light,
        appLanguage: AppLanguage.italian,
        showScanDiagnostics: true,
        showScanHelp: false,
        keepCameraReady: false,
        confirmBeforeDelete: false,
        collectionViewMode: CollectionViewMode.minifyFull,
        collectionSortBy: CollectionSortBy.quantity,
        collectionSortDescending: true,
        fastLogEnabled: true,
        fastLogFields: {FastLogField.condition},
      ),
    );

    final settings = await repository.load();

    expect(settings.defaultCondition, CardCondition.lightPlayed);
    expect(settings.defaultEdition, CardEdition.first);
    expect(settings.language, 'DE');
    expect(settings.themeMode, AppThemeMode.light);
    expect(settings.appLanguage, AppLanguage.italian);
    expect(settings.showScanDiagnostics, isTrue);
    expect(settings.showScanHelp, isFalse);
    expect(settings.keepCameraReady, isFalse);
    expect(settings.confirmBeforeDelete, isFalse);
    expect(settings.collectionViewMode, CollectionViewMode.minifyFull);
    expect(settings.collectionSortBy, CollectionSortBy.quantity);
    expect(settings.collectionSortDescending, isTrue);
    expect(settings.fastLogEnabled, isTrue);
    expect(settings.fastLogFields, {FastLogField.condition});
  });

  // Step 24 removed the default-rarity preference. Rows written by an earlier
  // build are simply never read again — `meta` is an open key/value table, so a
  // leftover key is inert rather than something to migrate away.
  test('a leftover default_rarity row is ignored', () async {
    await metaDao.set('settings.default_rarity', 'Secret Rare');

    final settings = await repository.load();

    expect(settings.defaultCondition, CardCondition.nearMint);
    expect(settings.language, 'EN');
  });

  test('a malformed boolean falls back to its default', () async {
    await metaDao.set('settings.show_scan_diagnostics', 'yes');
    await metaDao.set('settings.show_scan_help', '1');
    await metaDao.set('settings.keep_camera_ready', 'off');
    await metaDao.set('settings.confirm_before_delete', '');

    final settings = await repository.load();

    expect(settings.showScanDiagnostics, isFalse);
    expect(settings.showScanHelp, isTrue);
    expect(settings.keepCameraReady, isTrue);
    expect(settings.confirmBeforeDelete, isTrue);
  });

  test('save persists enums by name, never by ordinal', () async {
    await repository.save(
      const AppSettings(
        defaultCondition: CardCondition.poor,
        defaultEdition: CardEdition.limited,
        themeMode: AppThemeMode.system,
        appLanguage: AppLanguage.italian,
        collectionViewMode: CollectionViewMode.minifyStandard,
        collectionSortBy: CollectionSortBy.dateAdded,
      ),
    );

    expect(await metaDao.get('settings.default_condition'), 'POOR');
    expect(await metaDao.get('settings.default_edition'), 'LIMITED');
    expect(await metaDao.get('settings.theme_mode'), 'SYSTEM');
    expect(await metaDao.get('settings.app_language'), 'ITALIAN');
    expect(
      await metaDao.get('settings.collection_view_mode'),
      'MINIFY_STANDARD',
    );
    expect(await metaDao.get('settings.collection_sort_by'), 'DATE_ADDED');
  });

  test('an unrecognized stored value falls back to its default', () async {
    // A downgrade past a future enum member, or a hand-edited database.
    // Settings load during app start, so this must not throw.
    await metaDao.set('settings.default_condition', 'PRISTINE');
    await metaDao.set('settings.default_edition', 'SOMETHING_NEW');
    await metaDao.set('settings.theme_mode', 'SEPIA');
    await metaDao.set('settings.app_language', 'KLINGON');
    await metaDao.set('settings.collection_view_mode', 'TINY');
    await metaDao.set('settings.collection_sort_by', 'RARITY');

    final settings = await repository.load();

    expect(settings.defaultCondition, CardCondition.nearMint);
    expect(settings.defaultEdition, CardEdition.unlimited);
    expect(settings.themeMode, AppThemeMode.dark);
    expect(settings.appLanguage, AppLanguage.english);
    expect(settings.collectionViewMode, CollectionViewMode.minifyStandard);
    expect(settings.collectionSortBy, CollectionSortBy.name);
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
    await metaDao.set('settings.fast_log_fields', 'SOMETHING');

    final settings = await repository.load();

    expect(settings.defaultCondition, CardCondition.mint);
    expect(settings.language, 'JP');
    expect(settings.themeMode, AppThemeMode.light);
    expect(settings.defaultEdition, CardEdition.unlimited);
  });

  group('fast log fields', () {
    // A `{...set, field}` literal preserves insertion order, so without the
    // sort at write time the identical configuration would produce two
    // different stored values depending on which switch was flipped first.
    test('are stored in declaration order, not tick order', () async {
      await repository.save(
        const AppSettings(
          fastLogFields: {FastLogField.language, FastLogField.condition},
        ),
      );

      expect(
        await metaDao.get('settings.fast_log_fields'),
        'CONDITION,LANGUAGE',
      );
    });

    test('are persisted by name, never by ordinal', () async {
      await repository.save(
        const AppSettings(fastLogFields: {FastLogField.edition}),
      );

      expect(await metaDao.get('settings.fast_log_fields'), 'EDITION');
    });

    // "Ask about nothing" is the maximal Fast log and a perfectly reachable
    // configuration, so it has to round-trip rather than being read back as
    // "never configured".
    test('an explicitly empty set round-trips as empty', () async {
      await repository.save(
        const AppSettings(
          fastLogEnabled: true,
          fastLogFields: <FastLogField>{},
        ),
      );

      expect(await metaDao.get('settings.fast_log_fields'), '');
      expect((await repository.load()).fastLogFields, isEmpty);
    });

    // Note this asserts the *observable* result, which today is the same one an
    // explicitly empty value gives, because the default is itself empty. The
    // guard still distinguishes the two on purpose: a value it cannot read at
    // all falls back, so if the default ever becomes non-empty a corrupt row
    // degrades toward asking *more*, never toward logging details silently.
    test('a wholly unreadable value falls back to the default', () async {
      await metaDao.set('settings.fast_log_fields', 'yes');

      expect((await repository.load()).fastLogFields, isEmpty);
    });

    test('an unreadable member is dropped and the rest survive', () async {
      await metaDao.set(
        'settings.fast_log_fields',
        'CONDITION,RARITY,LANGUAGE',
      );

      final settings = await repository.load();

      expect(settings.fastLogFields, {
        FastLogField.condition,
        FastLogField.language,
      });
    });

    test('whitespace and empty members are tolerated', () async {
      await metaDao.set('settings.fast_log_fields', ' CONDITION , ,EDITION ');

      final settings = await repository.load();

      expect(settings.fastLogFields, {
        FastLogField.condition,
        FastLogField.edition,
      });
    });

    test('a malformed enabled flag falls back to its default', () async {
      await metaDao.set('settings.fast_log_enabled', 'yes');

      final settings = await repository.load();

      expect(settings.fastLogEnabled, isFalse);
    });
  });
}
