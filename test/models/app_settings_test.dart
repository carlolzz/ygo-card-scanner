import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/models/app_settings.dart';
import 'package:ygo_scanner/models/collection_view_mode.dart';
import 'package:ygo_scanner/models/fast_log_field.dart';

/// The Fast log rule. It lives on [AppSettings] precisely so that both logging
/// flows and the Settings screen read one definition, which makes this the
/// single place it is worth pinning.
void main() {
  // Two widgets fall back to this value while settings resolve, and the
  // collection screen renders a grid or a list off it, so the default is worth
  // naming here rather than only inferring it from what a screen draws.
  test('the collection opens on the captioned grid by default', () {
    expect(
      const AppSettings().collectionViewMode,
      CollectionViewMode.minifyStandard,
    );
  });

  group('fastLogActive', () {
    test('is false while the switch is off, whatever the fields hold', () {
      expect(const AppSettings().fastLogActive, isFalse);
      expect(
        const AppSettings(
          fastLogFields: {FastLogField.condition},
        ).fastLogActive,
        isFalse,
      );
      expect(
        const AppSettings(fastLogFields: <FastLogField>{}).fastLogActive,
        isFalse,
      );
    });

    // The auto-disable rule: ticked means "still ask me", so ticking every
    // field asks for everything and Fast log suppresses nothing.
    test('is false when enabled with every field ticked', () {
      const settings = AppSettings(
        fastLogEnabled: true,
        fastLogFields: {
          FastLogField.condition,
          FastLogField.edition,
          FastLogField.language,
        },
      );

      expect(settings.fastLogActive, isFalse);
    });

    test('is true when enabled with nothing ticked', () {
      expect(const AppSettings(fastLogEnabled: true).fastLogActive, isTrue);
    });

    test('is true when enabled with any single field left unticked', () {
      for (final untickedField in FastLogField.values) {
        final settings = AppSettings(
          fastLogEnabled: true,
          fastLogFields: FastLogField.values
              .where((field) => field != untickedField)
              .toSet(),
        );

        expect(
          settings.fastLogActive,
          isTrue,
          reason: 'unticking ${untickedField.label} should activate Fast log',
        );
      }
    });
  });

  group('fastLogAskedFields', () {
    test('is everything whenever Fast log is inactive', () {
      // Both reasons it can be inactive.
      expect(
        const AppSettings(
          fastLogFields: {FastLogField.condition},
        ).fastLogAskedFields,
        FastLogField.values.toSet(),
      );
      expect(
        const AppSettings(
          fastLogEnabled: true,
          fastLogFields: {
            FastLogField.condition,
            FastLogField.edition,
            FastLogField.language,
          },
        ).fastLogAskedFields,
        FastLogField.values.toSet(),
      );
    });

    test('is the configured set while Fast log is active', () {
      expect(
        const AppSettings(
          fastLogEnabled: true,
          fastLogFields: {FastLogField.language},
        ).fastLogAskedFields,
        {FastLogField.language},
      );
      expect(
        const AppSettings(fastLogEnabled: true).fastLogAskedFields,
        isEmpty,
      );
    });
  });

  test('copyWith carries the fast log fields through untouched', () {
    const settings = AppSettings(
      fastLogEnabled: true,
      fastLogFields: {FastLogField.edition},
    );

    final next = settings.copyWith(language: 'IT');

    expect(next.fastLogEnabled, isTrue);
    expect(next.fastLogFields, {FastLogField.edition});
  });

  test('copyWith takes the empty set as a real value, not a no-op', () {
    const settings = AppSettings(
      fastLogEnabled: true,
      fastLogFields: {FastLogField.edition},
    );

    // The empty set *is* the clear, which is why there is no clear flag.
    expect(settings.copyWith(fastLogFields: const {}).fastLogFields, isEmpty);
  });
}
