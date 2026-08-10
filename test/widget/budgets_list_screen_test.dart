import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:finos_app/features/budgets/presentation/budget_form_screen.dart';
import 'package:finos_app/features/budgets/presentation/budgets_list_screen.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the Budgets tab (FR-04, docs/UI_DESIGN.md §19–§20).
///
/// Spending is seeded as real transactions rather than stubbed, so these cover
/// the whole read path: transactions → consumption query → derived progress →
/// rendered card.
///
/// Each test closes the database before returning: the underlying streams carry
/// an open-timeout timer, and the test framework asserts no timers are pending
/// once the widget tree is disposed.
void main() {
  /// Creates an in-memory database with an account and one expense category to
  /// hang budgets and spending off.
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

  Future<void> pumpScreen(WidgetTester tester, AppDatabase database) async {
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
  }

  /// Adds a budget covering the current calendar month.
  Future<void> addBudget(
    AppDatabase database, {
    String id = 'budget-food',
    String categoryId = 'test-food',
    int amountMinor = 1000000,
    BudgetPeriod period = BudgetPeriod.monthly,
    BudgetStatus status = BudgetStatus.active,
  }) async {
    final now = DateTime.now();
    await BudgetDao(database).insertOne(
      BudgetsCompanion.insert(
        id: id,
        categoryId: categoryId,
        amountMinor: amountMinor,
        period: period,
        startDate: DateTime(now.year, now.month),
        status: Value(status),
      ),
    );
  }

  /// Records a transaction dated today, so it falls inside the current window.
  Future<void> addExpense(
    AppDatabase database,
    String id,
    int amountMinor, {
    String? categoryId = 'test-food',
    TransactionType type = TransactionType.expense,
  }) async {
    await TransactionDao(database).insertOne(
      TransactionsCompanion.insert(
        id: id,
        type: type,
        amountMinor: amountMinor,
        accountId: 'acct-main',
        categoryId: Value(categoryId),
        date: DateTime.now(),
      ),
    );
  }

  testWidgets('shows an empty state when there are no budgets', (tester) async {
    final database = await seedDatabase();
    await pumpScreen(tester, database);

    expect(find.text('No budgets yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add budget'), findsOneWidget);

    await database.close();
  });

  testWidgets('empty-state button opens the budget form', (tester) async {
    final database = await seedDatabase();
    await pumpScreen(tester, database);

    await tester.tap(find.widgetWithText(FilledButton, 'Add budget'));
    await tester.pumpAndSettle();

    expect(find.byType(BudgetFormScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('the add button opens the budget form', (tester) async {
    final database = await seedDatabase();
    await addBudget(database);
    await pumpScreen(tester, database);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(BudgetFormScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('renders spending against the limit and what remains', (
    tester,
  ) async {
    final database = await seedDatabase();
    await addBudget(database); // limit ৳10,000
    await addExpense(database, 'tx-1', 200000); // ৳2,000
    await addExpense(database, 'tx-2', 150000); // ৳1,500
    await addExpense(database, 'tx-3', 120000); // ৳1,200
    await pumpScreen(tester, database);

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    // The docs/DATA_MODEL.md §24 worked example: 4,700 spent of 10,000.
    expect(find.text('৳4,700.00 / ৳10,000.00'), findsOneWidget);
    expect(find.text('৳5,300.00 remaining'), findsOneWidget);
    expect(find.text('On track'), findsOneWidget);

    await database.close();
  });

  testWidgets('an untouched budget shows its full limit remaining', (
    tester,
  ) async {
    final database = await seedDatabase();
    await addBudget(database);
    await pumpScreen(tester, database);

    expect(find.text('৳0.00 / ৳10,000.00'), findsOneWidget);
    expect(find.text('৳10,000.00 remaining'), findsOneWidget);
    expect(find.text('On track'), findsOneWidget);

    await database.close();
  });

  testWidgets('warns textually when a budget is near its limit', (
    tester,
  ) async {
    final database = await seedDatabase();
    await addBudget(database);
    await addExpense(database, 'tx-1', 850000); // 85% of the limit
    await pumpScreen(tester, database);

    // The state is spelled out, not signalled by colour alone
    // (docs/UI_DESIGN.md §20).
    expect(find.text('Near limit'), findsOneWidget);
    expect(find.text('৳1,500.00 remaining'), findsOneWidget);

    await database.close();
  });

  testWidgets('reports how far over budget an exceeded budget is', (
    tester,
  ) async {
    final database = await seedDatabase();
    await addBudget(database);
    await addExpense(database, 'tx-1', 1050000); // ৳10,500 of a ৳10,000 limit
    await pumpScreen(tester, database);

    expect(find.text('Over budget'), findsOneWidget);
    expect(find.text('৳500.00 over budget'), findsOneWidget);
    expect(find.text('৳10,500.00 / ৳10,000.00'), findsOneWidget);

    await database.close();
  });

  testWidgets('income does not consume the budget', (tester) async {
    final database = await seedDatabase();
    await CategoryDao(database).insertOne(
      CategoriesCompanion.insert(
        id: 'test-salary',
        name: 'Salary',
        type: CategoryType.income,
      ),
    );
    await addBudget(database);
    await addExpense(
      database,
      'tx-income',
      900000,
      categoryId: 'test-salary',
      type: TransactionType.income,
    );
    await addExpense(database, 'tx-food', 100000);
    await pumpScreen(tester, database);

    // Only the ৳1,000 expense counts (docs/DATA_MODEL.md §17, §24).
    expect(find.text('৳1,000.00 / ৳10,000.00'), findsOneWidget);

    await database.close();
  });

  testWidgets('groups budgets by period', (tester) async {
    final database = await seedDatabase();
    await CategoryDao(database).insertOne(
      CategoriesCompanion.insert(
        id: 'test-transport',
        name: 'Transport',
        type: CategoryType.expense,
      ),
    );
    await addBudget(database);
    await addBudget(
      database,
      id: 'budget-transport',
      categoryId: 'test-transport',
      period: BudgetPeriod.weekly,
      amountMinor: 500000,
    );
    await pumpScreen(tester, database);

    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);

    await database.close();
  });

  testWidgets('collects archived budgets in their own section', (tester) async {
    final database = await seedDatabase();
    await addBudget(database, status: BudgetStatus.archived);
    await pumpScreen(tester, database);

    expect(find.text('Archived'), findsWidgets);
    expect(find.text('Monthly'), findsNothing);

    await database.close();
  });

  testWidgets('archiving a budget moves it into the archived section', (
    tester,
  ) async {
    final database = await seedDatabase();
    await addBudget(database);
    await pumpScreen(tester, database);

    expect(find.text('Monthly'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Archived'), findsWidgets);
    expect(find.text('Monthly'), findsNothing);

    await database.close();
  });

  testWidgets('deleting a budget asks for confirmation first', (tester) async {
    final database = await seedDatabase();
    await addBudget(database);
    await pumpScreen(tester, database);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this budget?'), findsOneWidget);

    // Cancelling leaves the budget in place.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('No budgets yet'), findsOneWidget);
    expect(await BudgetDao(database).getById('budget-food'), isNull);

    await database.close();
  });

  testWidgets('the edit menu item opens the form for that budget', (
    tester,
  ) async {
    final database = await seedDatabase();
    await addBudget(database);
    await pumpScreen(tester, database);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(BudgetFormScreen), findsOneWidget);
    expect(find.text('Edit budget'), findsOneWidget);

    await database.close();
  });

  testWidgets('a new expense immediately updates the budget card', (
    tester,
  ) async {
    final database = await seedDatabase();
    await addBudget(database);
    await pumpScreen(tester, database);

    expect(find.text('৳0.00 / ৳10,000.00'), findsOneWidget);

    // The progress provider watches the transaction stream, so recording an
    // expense must move the card without a manual refresh.
    await addExpense(database, 'tx-late', 250000);
    await tester.pumpAndSettle();

    expect(find.text('৳2,500.00 / ৳10,000.00'), findsOneWidget);
    expect(find.text('৳7,500.00 remaining'), findsOneWidget);

    await database.close();
  });
}
