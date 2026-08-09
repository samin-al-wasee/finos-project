import 'package:finos_app/app/app.dart';
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Wraps [child] with an in-memory database so tests never touch disk.
  Widget buildApp({required AppDatabase database}) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: const FinOSApp(),
    );
  }

  testWidgets('renders the bottom navigation shell with four destinations', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();

    await tester.pumpWidget(buildApp(database: database));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Budgets'), findsOneWidget);

    // Closing the database before the test body ends shuts down drift's
    // stream-query store, so no internal timers remain pending when the test
    // framework disposes the widget tree and verifies invariants.
    await database.close();
  });

  testWidgets(
    'shows an empty state on the home tab when there are no accounts',
    (tester) async {
      final database = AppDatabase.inMemory();

      await tester.pumpWidget(buildApp(database: database));
      await tester.pumpAndSettle();

      expect(find.text('No accounts yet'), findsOneWidget);

      await database.close();
    },
  );
}
