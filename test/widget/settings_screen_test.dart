import 'package:finos_app/app/app.dart';
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/categories/presentation/categories_list_screen.dart';
import 'package:finos_app/features/settings/data/settings_dao.dart';
import 'package:finos_app/features/settings/domain/app_settings.dart';
import 'package:finos_app/features/settings/presentation/settings_screen.dart';
import 'package:finos_app/features/templates/presentation/templates_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the Settings screen (docs/ROADMAP.md §6.8).
///
/// Each test closes the database before returning: the preference stream keeps
/// drift's stream-query store alive, and the framework asserts no timers are
/// pending once the widget tree is disposed.
void main() {
  Future<void> pumpSettings(WidgetTester tester, AppDatabase database) async {
    // A tall viewport fits every section, so rows near the bottom (About) are
    // built and hit-testable without scrolling.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders every settings section', (tester) async {
    final database = AppDatabase.inMemory();
    await pumpSettings(tester, database);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Default currency'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Export backup'), findsOneWidget);
    expect(find.text('Import backup'), findsOneWidget);
    expect(find.text('FinOS'), findsOneWidget);

    await database.close();
  });

  testWidgets('shows the stored preferences as subtitles', (tester) async {
    final database = AppDatabase.inMemory();
    final dao = SettingsDao(database);
    await dao.put(SettingKeys.themePreference, 'DARK');
    await dao.put(SettingKeys.defaultCurrency, 'USD');

    await pumpSettings(tester, database);

    expect(find.text('Dark'), findsOneWidget);
    expect(find.textContaining('USD'), findsOneWidget);

    await database.close();
  });

  testWidgets('defaults to matching the system theme', (tester) async {
    final database = AppDatabase.inMemory();
    await pumpSettings(tester, database);

    expect(find.text('Match system'), findsOneWidget);

    await database.close();
  });

  testWidgets('choosing a theme persists it', (tester) async {
    final database = AppDatabase.inMemory();
    await pumpSettings(tester, database);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    final stored = await SettingsDao(
      database,
    ).getValue(SettingKeys.themePreference);
    expect(stored, 'DARK');
    // The subtitle reflects the new choice without a manual refresh.
    expect(find.text('Dark'), findsOneWidget);

    await database.close();
  });

  testWidgets('choosing a currency persists it', (tester) async {
    final database = AppDatabase.inMemory();
    await pumpSettings(tester, database);

    await tester.tap(find.text('Default currency'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('US Dollar'));
    await tester.pumpAndSettle();

    final stored = await SettingsDao(
      database,
    ).getValue(SettingKeys.defaultCurrency);
    expect(stored, 'USD');
    expect(find.textContaining('USD'), findsOneWidget);

    await database.close();
  });

  testWidgets('dismissing the theme picker changes nothing', (tester) async {
    final database = AppDatabase.inMemory();
    await pumpSettings(tester, database);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    // Tap outside the dialog to dismiss it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(await SettingsDao(database).getAll(), isEmpty);
    expect(find.text('Match system'), findsOneWidget);

    await database.close();
  });

  testWidgets('Categories opens the category management screen', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    await pumpSettings(tester, database);

    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoriesListScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('Templates opens the templates screen', (tester) async {
    final database = AppDatabase.inMemory();
    await pumpSettings(tester, database);

    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();

    expect(find.byType(TemplatesListScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('the data rows are enabled', (tester) async {
    final database = AppDatabase.inMemory();
    await pumpSettings(tester, database);

    for (final label in ['Export backup', 'Import backup']) {
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
      );
      expect(tile.enabled, isTrue, reason: '"$label" should be tappable');
    }

    await database.close();
  });

  testWidgets('About states that data stays on the device', (tester) async {
    final database = AppDatabase.inMemory();
    await pumpSettings(tester, database);

    // The local-first guarantee is the product's main privacy claim (FR-09).
    expect(find.textContaining('only on this device'), findsOneWidget);

    await database.close();
  });

  group('theme applied to the app', () {
    testWidgets('a stored dark preference renders the app in dark mode', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      await SettingsDao(database).put(SettingKeys.themePreference, 'DARK');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const FinOSApp(),
        ),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);

      await database.close();
    });

    testWidgets('no stored preference follows the system', (tester) async {
      final database = AppDatabase.inMemory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const FinOSApp(),
        ),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.system);

      await database.close();
    });

    testWidgets('changing the theme in Settings updates the app', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const FinOSApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );

      // Home → Settings → Theme → Light.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light').last);
      await tester.pumpAndSettle();

      // The root widget watches the preference stream, so the whole app
      // re-themes without a restart.
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );

      await database.close();
    });
  });

  group('entry point', () {
    testWidgets('the Home tab opens Settings', (tester) async {
      final database = AppDatabase.inMemory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const FinOSApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);

      await database.close();
    });

    testWidgets('a new account defaults to the chosen currency', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      await SettingsDao(database).put(SettingKeys.defaultCurrency, 'EUR');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const FinOSApp(),
        ),
      );
      await tester.pumpAndSettle();

      // The home empty state leads to the account form.
      await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
      await tester.pumpAndSettle();

      // The currency dropdown starts on the preference, not the BDT fallback.
      expect(find.text('EUR (€)'), findsOneWidget);

      await database.close();
    });
  });
}
