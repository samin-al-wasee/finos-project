import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/presentation/budget_details_screen.dart';
import 'package:finos_app/features/budgets/presentation/budgets_list_screen.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the budget history screen (docs/ROADMAP.md §8.3).
void main() {
  Future<AppDatabase> seedDatabase() async {
    final database = AppDatabase.inMemory();
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-main',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await CategoryDao(database).insertOne(
      CategoriesCompanion.insert(
        id: 'test-food',
        name: 'Food',
        type: CategoryType.expense,
      ),
    );
    return database;
  }

  Future<void> pumpDetails(
    WidgetTester tester,
    AppDatabase database,
    String budgetId,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: BudgetDetailsScreen(budgetId: budgetId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addBudget(
    AppDatabase database, {
    String id = 'budget-food',
    BudgetPeriod period = BudgetPeriod.monthly,
    DateTime? startDate,
    bool rolloverEnabled = false,
  }) async {
    await BudgetDao(database).insertOne(
      BudgetsCompanion.insert(
        id: id,
        categoryId: const Value('test-food'),
        amountMinor: 1000000,
        period: period,
        startDate: startDate ?? DateTime(2020),
        rolloverEnabled: Value(rolloverEnabled),
      ),
    );
  }

  Future<void> addExpense(
    AppDatabase database,
    String id,
    int amountMinor,
    DateTime date,
  ) async {
    await TransactionDao(database).insertOne(
      TransactionsCompanion.insert(
        id: id,
        type: TransactionType.expense,
        amountMinor: amountMinor,
        accountId: 'acct-main',
        categoryId: const Value('test-food'),
        date: date,
      ),
    );
  }

  testWidgets('shows the current period at the top', (tester) async {
    final database = await seedDatabase();
    await addBudget(database);
    await addExpense(database, 'tx-now', 250000, DateTime.now());
    await pumpDetails(tester, database, 'budget-food');

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('৳2,500.00 / ৳10,000.00'), findsOneWidget);

    await database.close();
  });

  testWidgets('shows spending from a previous month as history', (
    tester,
  ) async {
    final database = await seedDatabase();
    await addBudget(database);
    final lastMonth = DateTime(
      DateTime.now().year,
      DateTime.now().month - 1,
      10,
    );
    await addExpense(database, 'tx-last-month', 400000, lastMonth);
    await pumpDetails(tester, database, 'budget-food');

    expect(find.text('History'), findsOneWidget);
    expect(find.text('৳4,000.00 / ৳10,000.00'), findsOneWidget);
    expect(find.text('No earlier periods yet.'), findsNothing);

    await database.close();
  });

  testWidgets('a brand-new budget has no earlier periods', (tester) async {
    final database = await seedDatabase();
    await addBudget(database, startDate: DateTime.now());
    await pumpDetails(tester, database, 'budget-food');

    expect(find.text('No earlier periods yet.'), findsOneWidget);

    await database.close();
  });

  testWidgets('history stops at the budget\'s own start date', (tester) async {
    final database = await seedDatabase();
    final now = DateTime.now();
    // Started two months ago: at most one prior period (last month) should
    // appear, never one from three months back.
    await addBudget(database, startDate: DateTime(now.year, now.month - 2, 1));
    await addExpense(
      database,
      'tx-old',
      100000,
      DateTime(now.year, now.month - 3, 15),
    );
    await pumpDetails(tester, database, 'budget-food');

    // The too-old spending must not surface as a ৳1,000.00 history entry.
    expect(find.text('৳1,000.00 / ৳10,000.00'), findsNothing);

    await database.close();
  });

  group('rollover caption (docs/adr/008-budget-rollover.md)', () {
    testWidgets('a non-rollover budget shows no carry-in caption', (
      tester,
    ) async {
      final database = await seedDatabase();
      await addBudget(database);
      await pumpDetails(tester, database, 'budget-food');

      expect(find.textContaining('carried in'), findsNothing);
      expect(find.textContaining('carried over as a deficit'), findsNothing);

      await database.close();
    });

    testWidgets(
      'a rollover budget with an unspent prior period shows the carry-in '
      'caption on the current period tile',
      (tester) async {
        final database = await seedDatabase();
        final now = DateTime.now();
        final lastMonth = shiftedBudgetWindow(
          BudgetPeriod.monthly,
          reference: now,
          offset: -1,
        )!;
        await addBudget(
          database,
          startDate: lastMonth.from,
          rolloverEnabled: true,
        );
        // Last month: 3,000 spent of a 10,000 limit → 7,000 unspent.
        await addExpense(
          database,
          'tx-last-month',
          300000,
          lastMonth.from.add(const Duration(days: 5)),
        );
        await pumpDetails(tester, database, 'budget-food');

        expect(find.text('Includes ৳7,000.00 carried in'), findsOneWidget);

        await database.close();
      },
    );
  });

  testWidgets('a custom-period budget has no repeating history', (
    tester,
  ) async {
    final database = await seedDatabase();
    await BudgetDao(database).insertOne(
      BudgetsCompanion.insert(
        id: 'budget-custom',
        categoryId: const Value('test-food'),
        amountMinor: 500000,
        period: BudgetPeriod.custom,
        startDate: DateTime(2026, 1, 1),
        endDate: Value(DateTime(2026, 1, 31)),
      ),
    );
    await pumpDetails(tester, database, 'budget-custom');

    expect(
      find.text('A one-time budget has no repeating history.'),
      findsOneWidget,
    );

    await database.close();
  });

  testWidgets('tapping a budget card in the list opens its history', (
    tester,
  ) async {
    final database = await seedDatabase();
    await addBudget(database);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const BudgetsListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();

    expect(find.byType(BudgetDetailsScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Budget history'), findsOneWidget);

    await database.close();
  });
}
