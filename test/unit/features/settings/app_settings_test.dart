import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/settings/domain/app_settings.dart';
import 'package:finos_app/features/settings/domain/theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the typed view over the key-value preferences table.
///
/// The central guarantee: a database with missing, unknown, or corrupt
/// preference rows still yields usable settings. A bad row must never be able to
/// make the app unlaunchable, because the theme is read while the root widget
/// builds.
void main() {
  PreferenceRow row(String key, String value) =>
      PreferenceRow(key: key, value: value, updatedAt: DateTime(2026, 8, 10));

  group('defaults', () {
    test('no rows yields system theme and the fallback currency', () {
      final settings = AppSettings.fromRows(const []);

      expect(settings.themePreference, ThemePreference.system);
      expect(settings.defaultCurrency, 'BDT');
    });

    test('the const constructor matches the empty-row defaults', () {
      // The root widget uses `const AppSettings()` while preferences load, so
      // the two must agree or the theme would flicker on first paint.
      expect(const AppSettings(), AppSettings.fromRows(const []));
    });

    test('one stored setting leaves the other at its default', () {
      final settings = AppSettings.fromRows([
        row(SettingKeys.defaultCurrency, 'USD'),
      ]);

      expect(settings.defaultCurrency, 'USD');
      expect(settings.themePreference, ThemePreference.system);
    });
  });

  group('parsing stored rows', () {
    test('reads each theme preference', () {
      for (final preference in ThemePreference.values) {
        final settings = AppSettings.fromRows([
          row(
            SettingKeys.themePreference,
            themePreferenceToStorage(preference),
          ),
        ]);
        expect(settings.themePreference, preference);
      }
    });

    test('reads the default currency', () {
      final settings = AppSettings.fromRows([
        row(SettingKeys.defaultCurrency, 'EUR'),
      ]);

      expect(settings.defaultCurrency, 'EUR');
    });

    test('ignores unknown keys', () {
      // A database written by a newer version must still open in an older one.
      final settings = AppSettings.fromRows([
        row('a_setting_from_the_future', 'whatever'),
        row(SettingKeys.themePreference, 'DARK'),
      ]);

      expect(settings.themePreference, ThemePreference.dark);
      expect(settings.defaultCurrency, 'BDT');
    });

    test('falls back rather than throwing on an unrecognised theme', () {
      final settings = AppSettings.fromRows([
        row(SettingKeys.themePreference, 'NEON'),
      ]);

      expect(settings.themePreference, ThemePreference.system);
    });
  });

  group('theme mode mapping', () {
    test('maps each preference onto its ThemeMode', () {
      expect(themeModeFor(ThemePreference.system), ThemeMode.system);
      expect(themeModeFor(ThemePreference.light), ThemeMode.light);
      expect(themeModeFor(ThemePreference.dark), ThemeMode.dark);
    });

    test('storage values round-trip', () {
      for (final preference in ThemePreference.values) {
        expect(
          themePreferenceFromStorage(themePreferenceToStorage(preference)),
          preference,
        );
      }
    });

    test('a null stored value is the system default', () {
      expect(themePreferenceFromStorage(null), ThemePreference.system);
    });
  });

  group('copyWith and equality', () {
    test('copyWith replaces only the named field', () {
      const settings = AppSettings(
        themePreference: ThemePreference.dark,
        defaultCurrency: 'USD',
      );

      final recoloured = settings.copyWith(
        themePreference: ThemePreference.light,
      );
      expect(recoloured.themePreference, ThemePreference.light);
      expect(recoloured.defaultCurrency, 'USD');
    });

    test('value equality compares both fields', () {
      const a = AppSettings(
        themePreference: ThemePreference.dark,
        defaultCurrency: 'USD',
      );
      const b = AppSettings(
        themePreference: ThemePreference.dark,
        defaultCurrency: 'USD',
      );
      const c = AppSettings(
        themePreference: ThemePreference.dark,
        defaultCurrency: 'EUR',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
