import 'package:finos_app/app/app_shell.dart';
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces the reported bug: opening the keyboard on a modest-height
/// screen and typing `@` in the quick entry bar to show its suggestion
/// dropdown overflows the app shell itself (distinct from
/// quick_entry_bar_test.dart, which only constrains the bar in isolation,
/// not the full shell around it).
void main() {
  testWidgets(
    'AppShell does not overflow when the keyboard is open and the '
    'quick entry suggestion dropdown is showing',
    (tester) async {
      final database = AppDatabase.inMemory();

      // A modest phone screen height, comparable to smaller Android devices.
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AppShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate the on-screen keyboard opening, the way it would when the
      // user taps the quick entry text field.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '@');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await database.close();
    },
  );
}
