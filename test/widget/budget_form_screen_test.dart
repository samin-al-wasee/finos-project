import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/presentation/budget_form_screen.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the add/edit budget form (FR-04).
///
/// Each test closes the database before returning: the category stream carries
/// an open-timeout timer, and the test framework asserts no timers are pending
/// once the widget tree is disposed.
void main() {
  /// Creates an in-memory database seeded with the categories these tests pick
  /// from: one active expense, one income, one archived expense.
  Future<AppDatabase> seedDatabase() async {
    final database = AppDatabase.inMemory();
    final categories = CategoryDao(database);
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-food',
        name: 'Test Food',
        type: CategoryType.expense,
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-salary',
        name: 'Test Salary',
        type: CategoryType.income,
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-archived',
        name: 'Test Archived',
        type: CategoryType.expense,
        status: Value(CategoryStatus.archived),
      ),
    );
    return database;
  }

  Future<void> pumpForm(
    WidgetTester tester,
    AppDatabase database, {
    BudgetRow? initial,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: BudgetFormScreen(initial: initial),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Picks "Test Food" from the category dropdown.
  Future<void> chooseFoodCategory(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Food').last);
    await tester.pumpAndSettle();
  }

  testWidgets('offers only active expense categories', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    // Budgets cap spending, so income and archived categories are not offered
    // (docs/DATA_MODEL.md §24).
    expect(find.text('Test Food'), findsWidgets);
    expect(find.text('Test Salary'), findsNothing);
    expect(find.text('Test Archived'), findsNothing);

    await database.close();
  });

  testWidgets('defaults to a monthly period', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    expect(find.text('Monthly'), findsOneWidget);
    expect(find.textContaining('reset every month'), findsOneWidget);

    await database.close();
  });

  testWidgets('requires a category', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.enterText(find.byType(TextFormField), '10000');
    await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a category'), findsOneWidget);
    expect(await BudgetDao(database).getAll(), isEmpty);

    await database.close();
  });

  testWidgets('requires a limit', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a limit'), findsOneWidget);
    expect(await BudgetDao(database).getAll(), isEmpty);

    await database.close();
  });

  testWidgets('rejects a zero limit', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.enterText(find.byType(TextFormField), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
    await tester.pumpAndSettle();

    expect(find.text('Limit must be greater than zero'), findsOneWidget);
    expect(await BudgetDao(database).getAll(), isEmpty);

    await database.close();
  });

  testWidgets('rejects a non-numeric limit', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid amount'), findsOneWidget);
    expect(await BudgetDao(database).getAll(), isEmpty);

    await database.close();
  });

  testWidgets('creates a budget with the limit in minor units', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await chooseFoodCategory(tester);
    await tester.enterText(find.byType(TextFormField), '10000.50');
    await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
    await tester.pumpAndSettle();

    final rows = await BudgetDao(database).getAll();
    expect(rows, hasLength(1));
    expect(rows.single.categoryId, 'test-food');
    // Stored as integer minor units, never floating point
    // (docs/DATA_MODEL.md §4).
    expect(rows.single.amountMinor, 1000050);
    expect(rows.single.period, BudgetPeriod.monthly);
    expect(rows.single.endDate, isNull);

    await database.close();
  });

  testWidgets('a custom period asks for an end date before saving', (
    tester,
  ) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await chooseFoodCategory(tester);
    await tester.enterText(find.byType(TextFormField), '5000');

    await tester.tap(find.byType(DropdownButtonFormField<BudgetPeriod>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();

    expect(find.text('End date'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
    await tester.pumpAndSettle();

    expect(find.text('Choose an end date for this budget'), findsOneWidget);
    expect(await BudgetDao(database).getAll(), isEmpty);

    await database.close();
  });

  testWidgets('surfaces a duplicate budget as a readable message', (
    tester,
  ) async {
    final database = await seedDatabase();
    final now = DateTime.now();
    await BudgetDao(database).insertOne(
      BudgetsCompanion.insert(
        id: 'budget-existing',
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
        startDate: DateTime(now.year, now.month),
      ),
    );
    await pumpForm(tester, database);

    await chooseFoodCategory(tester);
    await tester.enterText(find.byType(TextFormField), '20000');
    await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
    await tester.pumpAndSettle();

    // The rule is explained, not leaked as a database exception
    // (AGENTS.md §25).
    expect(find.textContaining('active budget already covers'), findsOneWidget);
    expect(await BudgetDao(database).getAll(), hasLength(1));

    await database.close();
  });

  group('editing', () {
    Future<BudgetRow> seedBudget(AppDatabase database) async {
      final dao = BudgetDao(database);
      await dao.insertOne(
        BudgetsCompanion.insert(
          id: 'budget-food',
          categoryId: 'test-food',
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 8, 1),
        ),
      );
      return (await dao.getById('budget-food'))!;
    }

    testWidgets('pre-fills the limit and locks the category', (tester) async {
      final database = await seedDatabase();
      await pumpForm(tester, database, initial: await seedBudget(database));

      expect(find.text('Edit budget'), findsOneWidget);
      expect(find.text('10000'), findsOneWidget);
      // The category is shown but not editable.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Test Food'), findsOneWidget);
      expect(
        find.text('A budget keeps the category it was created with'),
        findsOneWidget,
      );

      await database.close();
    });

    testWidgets('saves a changed limit', (tester) async {
      final database = await seedDatabase();
      await pumpForm(tester, database, initial: await seedBudget(database));

      await tester.enterText(find.byType(TextFormField), '15000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      final row = await BudgetDao(database).getById('budget-food');
      expect(row!.amountMinor, 1500000);
      expect(row.categoryId, 'test-food');

      await database.close();
    });

    testWidgets('rejects clearing the limit', (tester) async {
      final database = await seedDatabase();
      await pumpForm(tester, database, initial: await seedBudget(database));

      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a limit'), findsOneWidget);
      expect(
        (await BudgetDao(database).getById('budget-food'))!.amountMinor,
        1000000,
      );

      await database.close();
    });
  });
}
