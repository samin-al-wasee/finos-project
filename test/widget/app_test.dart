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

  testWidgets('navigating away from the shell does not collide hero tags', (
    tester,
  ) async {
    // Regression test: the shell keeps every tab alive in an IndexedStack, so
    // the Transactions, Accounts, and Budgets FABs all live in one route. While
    // they shared the default FloatingActionButton hero tag, pushing any route
    // threw "multiple heroes had the following tag" during the transition.
    final database = AppDatabase.inMemory();

    await tester.pumpWidget(buildApp(database: database));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await database.close();
  });

  testWidgets('each tab FAB carries a distinct hero tag', (tester) async {
    final database = AppDatabase.inMemory();

    await tester.pumpWidget(buildApp(database: database));
    await tester.pumpAndSettle();

    // The IndexedStack marks unselected tabs offstage, and finders skip those by
    // default — but they are still in the tree, which is exactly why their hero
    // tags can collide. So look at every tab, on-stage or not.
    final tags = tester
        .widgetList<FloatingActionButton>(
          find.byType(FloatingActionButton, skipOffstage: false),
        )
        .map((fab) => fab.heroTag)
        .toList();

    expect(tags, hasLength(3)); // Transactions, Accounts, Budgets
    expect(tags.toSet(), hasLength(tags.length));

    await database.close();
  });
}
