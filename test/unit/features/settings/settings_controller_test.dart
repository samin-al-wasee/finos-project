import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/settings/application/settings_controller.dart';
import 'package:finos_app/features/settings/data/settings_dao.dart';
import 'package:finos_app/features/settings/domain/app_settings.dart';
import 'package:finos_app/features/settings/domain/theme_preference.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [SettingsDao] and [SettingsController] — persistence, upsert
/// behaviour, and validation.
void main() {
  late AppDatabase database;
  late SettingsDao dao;
  late SettingsController controller;

  setUp(() {
    database = AppDatabase.inMemory();
    dao = SettingsDao(database);
    controller = SettingsController(dao);
  });

  tearDown(() async {
    await database.close();
  });

  group('SettingsDao', () {
    test('a fresh database has no preference rows', () async {
      // Nothing is seeded — every preference falls back to a default instead.
      expect(await dao.getAll(), isEmpty);
      expect(await dao.getValue('anything'), isNull);
    });

    test('put stores a value that can be read back', () async {
      await dao.put('some_key', 'some_value');

      expect(await dao.getValue('some_key'), 'some_value');
    });

    test('put overwrites rather than duplicating a key', () async {
      await dao.put('some_key', 'first');
      await dao.put('some_key', 'second');

      // The primary key is the setting key, so a setting has one row or none.
      expect(await dao.getAll(), hasLength(1));
      expect(await dao.getValue('some_key'), 'second');
    });

    test('keys are independent', () async {
      await dao.put('a', '1');
      await dao.put('b', '2');

      expect(await dao.getValue('a'), '1');
      expect(await dao.getValue('b'), '2');
      expect(await dao.getAll(), hasLength(2));
    });

    test('watchAll emits the stored rows', () async {
      await dao.put(SettingKeys.themePreference, 'DARK');

      final rows = await dao.watchAll().first;
      expect(rows, hasLength(1));
      expect(rows.single.key, SettingKeys.themePreference);
      expect(rows.single.value, 'DARK');
    });
  });

  group('theme preference', () {
    test('round-trips every preference through the database', () async {
      for (final preference in ThemePreference.values) {
        await controller.setThemePreference(preference);

        final settings = await controller.read();
        expect(settings.themePreference, preference);
      }
    });

    test('changing the theme does not disturb the currency', () async {
      await controller.setDefaultCurrency('USD');
      await controller.setThemePreference(ThemePreference.dark);

      final settings = await controller.read();
      expect(settings.themePreference, ThemePreference.dark);
      expect(settings.defaultCurrency, 'USD');
    });
  });

  group('default currency', () {
    test('stores a supported currency', () async {
      await controller.setDefaultCurrency('EUR');

      expect((await controller.read()).defaultCurrency, 'EUR');
    });

    test('rejects an unsupported code', () async {
      // An unsupported code has no symbol or decimal scale to format with
      // (docs/DATA_MODEL.md §5).
      expect(() => controller.setDefaultCurrency('XYZ'), throwsArgumentError);
    });

    test('rejects an empty code', () async {
      expect(() => controller.setDefaultCurrency(''), throwsArgumentError);
    });

    test('a rejected code leaves the stored value untouched', () async {
      await controller.setDefaultCurrency('USD');

      await expectLater(
        () => controller.setDefaultCurrency('XYZ'),
        throwsArgumentError,
      );

      expect((await controller.read()).defaultCurrency, 'USD');
      expect(await dao.getAll(), hasLength(1));
    });
  });

  group('read', () {
    test('returns defaults for an untouched database', () async {
      expect(await controller.read(), const AppSettings());
    });

    test('reflects every stored preference at once', () async {
      await controller.setThemePreference(ThemePreference.light);
      await controller.setDefaultCurrency('GBP');

      expect(
        await controller.read(),
        const AppSettings(
          themePreference: ThemePreference.light,
          defaultCurrency: 'GBP',
        ),
      );
    });
  });
}
