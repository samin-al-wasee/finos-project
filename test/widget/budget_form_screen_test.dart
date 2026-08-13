import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_scope.dart';
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
        categoryId: const Value('test-food'),
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

  group('scope-type selector (docs/adr/007-flexible-budget-scope.md)', () {
    testWidgets('defaults to single category, showing the category dropdown', (
      tester,
    ) async {
      final database = await seedDatabase();
      await pumpForm(tester, database);

      expect(find.text('Single category'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);

      await database.close();
    });

    testWidgets(
      'switching to multiple categories shows a checklist instead of the '
      'dropdown',
      (tester) async {
        final database = await seedDatabase();
        await pumpForm(tester, database);

        await tester.tap(find.byType(DropdownButtonFormField<BudgetScopeType>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Multiple categories').last);
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.byType(CheckboxListTile), findsWidgets);
        expect(find.text('Test Food'), findsOneWidget);
        // Income and archived categories are not offered, same as the single
        // dropdown (docs/DATA_MODEL.md §24).
        expect(find.text('Test Salary'), findsNothing);
        expect(find.text('Test Archived'), findsNothing);

        await database.close();
      },
    );

    testWidgets(
      'switching to uncategorised spending shows explanatory text and no '
      'category control',
      (tester) async {
        final database = await seedDatabase();
        await pumpForm(tester, database);

        await tester.tap(find.byType(DropdownButtonFormField<BudgetScopeType>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Uncategorised spending').last);
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(
          find.text('This budget covers every expense with no category.'),
          findsOneWidget,
        );

        await database.close();
      },
    );

    testWidgets(
      'switching to whole account shows explanatory text and no category '
      'control',
      (tester) async {
        final database = await seedDatabase();
        await pumpForm(tester, database);

        await tester.tap(find.byType(DropdownButtonFormField<BudgetScopeType>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Whole account').last);
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(
          find.text('This budget covers every expense, in every category.'),
          findsOneWidget,
        );

        await database.close();
      },
    );

    testWidgets('rejects a multi-category scope with fewer than 2 selected', (
      tester,
    ) async {
      final database = await seedDatabase();
      await CategoryDao(database).insertOne(
        CategoriesCompanion.insert(
          id: 'test-transport',
          name: 'Test Transport',
          type: CategoryType.expense,
        ),
      );
      await pumpForm(tester, database);

      await tester.tap(find.byType(DropdownButtonFormField<BudgetScopeType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Multiple categories').last);
      await tester.pumpAndSettle();

      // The checklist includes every built-in expense category too, so it
      // grows tall enough to push the rest of the form below the test
      // viewport — scroll each target into view before interacting with it,
      // using skipOffstage: false since it isn't onstage yet.
      final foodCheckbox = find.widgetWithText(
        CheckboxListTile,
        'Test Food',
        skipOffstage: false,
      );
      await tester.ensureVisible(foodCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(foodCheckbox);
      await tester.pumpAndSettle();

      final amountField = find.byType(TextFormField, skipOffstage: false);
      await tester.ensureVisible(amountField);
      await tester.pumpAndSettle();
      await tester.enterText(amountField, '10000');

      final addButton = find.widgetWithText(
        FilledButton,
        'Add budget',
        skipOffstage: false,
      );
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.text('Choose at least 2 categories'), findsOneWidget);
      expect(await BudgetDao(database).getAll(), isEmpty);

      await database.close();
    });

    testWidgets('creates a MULTI_CATEGORY budget from 2 selected categories', (
      tester,
    ) async {
      final database = await seedDatabase();
      await CategoryDao(database).insertOne(
        CategoriesCompanion.insert(
          id: 'test-transport',
          name: 'Test Transport',
          type: CategoryType.expense,
        ),
      );
      await pumpForm(tester, database);

      await tester.tap(find.byType(DropdownButtonFormField<BudgetScopeType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Multiple categories').last);
      await tester.pumpAndSettle();

      // See the note above: the checklist includes every built-in expense
      // category, so targets below it need scrolling into view first.
      final foodCheckbox = find.widgetWithText(
        CheckboxListTile,
        'Test Food',
        skipOffstage: false,
      );
      await tester.ensureVisible(foodCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(foodCheckbox);
      await tester.pumpAndSettle();

      final transportCheckbox = find.widgetWithText(
        CheckboxListTile,
        'Test Transport',
        skipOffstage: false,
      );
      await tester.ensureVisible(transportCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(transportCheckbox);
      await tester.pumpAndSettle();

      final amountField = find.byType(TextFormField, skipOffstage: false);
      await tester.ensureVisible(amountField);
      await tester.pumpAndSettle();
      await tester.enterText(amountField, '10000');

      final addButton = find.widgetWithText(
        FilledButton,
        'Add budget',
        skipOffstage: false,
      );
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      final dao = BudgetDao(database);
      final rows = await dao.getAll();
      expect(rows, hasLength(1));
      expect(rows.single.categoryId, isNull);
      expect(rows.single.scopeType, BudgetScopeType.multiCategory);
      expect(await dao.categoriesFor(rows.single.id), {
        'test-food',
        'test-transport',
      });

      await database.close();
    });

    testWidgets('creates an UNCATEGORIZED budget with no category picker', (
      tester,
    ) async {
      final database = await seedDatabase();
      await pumpForm(tester, database);

      await tester.tap(find.byType(DropdownButtonFormField<BudgetScopeType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uncategorised spending').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '10000');
      await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
      await tester.pumpAndSettle();

      final rows = await BudgetDao(database).getAll();
      expect(rows, hasLength(1));
      expect(rows.single.categoryId, isNull);
      expect(rows.single.scopeType, BudgetScopeType.uncategorized);

      await database.close();
    });

    testWidgets('creates a WHOLE_ACCOUNT budget with no category picker', (
      tester,
    ) async {
      final database = await seedDatabase();
      await pumpForm(tester, database);

      await tester.tap(find.byType(DropdownButtonFormField<BudgetScopeType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Whole account').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '10000');
      await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
      await tester.pumpAndSettle();

      final rows = await BudgetDao(database).getAll();
      expect(rows, hasLength(1));
      expect(rows.single.categoryId, isNull);
      expect(rows.single.scopeType, BudgetScopeType.wholeAccount);

      await database.close();
    });
  });

  group('editing', () {
    Future<BudgetRow> seedBudget(AppDatabase database) async {
      final dao = BudgetDao(database);
      await dao.insertOne(
        BudgetsCompanion.insert(
          id: 'budget-food',
          categoryId: const Value('test-food'),
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
      // The scope is shown but not editable (docs/adr/007-flexible-budget-scope.md).
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(
        find.byType(DropdownButtonFormField<BudgetScopeType>),
        findsNothing,
      );
      expect(find.text('Test Food'), findsOneWidget);
      expect(
        find.text('A budget keeps the scope it was created with'),
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
