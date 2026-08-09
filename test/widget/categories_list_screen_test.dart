import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/categories/presentation/categories_list_screen.dart';
import 'package:finos_app/features/categories/presentation/category_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppDatabase> pumpList(
    WidgetTester tester, {
    List<CategoriesCompanion> seed = const [],
  }) async {
    // A tall viewport fits the whole list (12 built-ins plus seeds, all three
    // sections) without scrolling, so off-screen tiles and their trailing
    // menus stay hit-testable.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = AppDatabase.inMemory();
    final dao = CategoryDao(database);
    for (final entry in seed) {
      await dao.insertOne(entry);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const CategoriesListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  CategoriesCompanion seedRow(
    String id,
    String name, {
    CategoryType type = CategoryType.expense,
    CategoryStatus status = CategoryStatus.active,
  }) {
    return CategoriesCompanion.insert(
      id: id,
      name: name,
      type: type,
      status: Value(status),
    );
  }

  /// Opens the trailing popup menu of the tile labelled [name].
  Future<void> openTileMenu(WidgetTester tester, String name) async {
    final tile = find.ancestor(
      of: find.text(name),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders built-in categories grouped by type', (tester) async {
    final database = await pumpList(tester);

    // Fresh database seeds the 12 built-ins.
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Archived'), findsNothing);

    // Built-ins carry the System badge.
    expect(find.text('System'), findsWidgets);

    // Not the empty state.
    expect(find.text('No categories yet'), findsNothing);

    await database.close();
  });

  testWidgets('FAB opens the create form', (tester) async {
    final database = await pumpList(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryFormScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Add category'), findsOneWidget);

    await database.close();
  });

  testWidgets('groups archived categories under an Archived header', (
    tester,
  ) async {
    final database = await pumpList(
      tester,
      seed: [seedRow('c1', 'Old', status: CategoryStatus.archived)],
    );

    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Old'), findsOneWidget);

    await database.close();
  });

  testWidgets('archives a category via its menu', (tester) async {
    final database = await pumpList(tester);
    final dao = CategoryDao(database);
    await dao.insertOne(seedRow('c1', 'Groceries'));
    await tester.pumpAndSettle();

    await openTileMenu(tester, 'Groceries');
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    // Lifecycle status persisted to the database.
    final row = await dao.getById('c1');
    expect(row!.status, CategoryStatus.archived);

    // Moved into the Archived section.
    expect(find.text('Archived'), findsOneWidget);

    await database.close();
  });

  testWidgets('restores an archived category via its menu', (tester) async {
    final database = await pumpList(
      tester,
      seed: [seedRow('c1', 'Groceries', status: CategoryStatus.archived)],
    );
    final dao = CategoryDao(database);

    await openTileMenu(tester, 'Groceries');
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    // Lifecycle status persisted to the database.
    final row = await dao.getById('c1');
    expect(row!.status, CategoryStatus.active);

    // Back to active, so the Archived section is gone.
    expect(find.text('Archived'), findsNothing);

    await database.close();
  });
}
