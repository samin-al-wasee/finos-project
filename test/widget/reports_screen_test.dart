import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/reports/presentation/reports_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppDatabase> pumpReports(WidgetTester tester) async {
    final database = AppDatabase.inMemory();
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ReportsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 1);
  final lastMonth = DateTime(thisMonth.year, thisMonth.month - 1, 1);

  testWidgets('shows an empty state when there is no activity', (tester) async {
    final database = await pumpReports(tester);

    expect(find.text('Nothing to report yet'), findsOneWidget);
    expect(find.text('Budget Performance'), findsNothing);

    await database.close();
  });

  testWidgets('renders income, expenses, and net for the default period', (
    tester,
  ) async {
    final database = await pumpReports(tester);
    final transactions = TransactionDao(database);

    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-income',
        type: TransactionType.income,
        amountMinor: 100000,
        accountId: 'acct-1',
        date: thisMonth,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-expense',
        type: TransactionType.expense,
        amountMinor: 30000,
        accountId: 'acct-1',
        date: thisMonth,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Income'), findsOneWidget);
    expect(find.text('৳1,000.00'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    // Appears on both the Expenses card and the uncategorized row in
    // "Spending by category", since this expense has no category.
    expect(find.text('৳300.00'), findsNWidgets(2));
    expect(find.text('Net'), findsOneWidget);
    // The Net card and the account's own row in "Cash Flow by Account".
    expect(find.text('৳700.00'), findsNWidgets(2));

    // No prior-month data to compare against.
    expect(find.text('No data for the previous period'), findsNWidgets(2));

    await database.close();
  });

  testWidgets('compares against the previous month by percentage', (
    tester,
  ) async {
    final database = await pumpReports(tester);
    final transactions = TransactionDao(database);

    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-expense-last',
        type: TransactionType.expense,
        amountMinor: 100000, // ৳1,000 last month
        accountId: 'acct-1',
        date: lastMonth,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-expense-this',
        type: TransactionType.expense,
        amountMinor: 150000, // ৳1,500 this month — a 50% increase
        accountId: 'acct-1',
        date: thisMonth,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('increased 50% vs previous month'), findsOneWidget);

    await database.close();
  });

  testWidgets('switching the period reloads the report', (tester) async {
    final database = await pumpReports(tester);
    final transactions = TransactionDao(database);

    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-this-month',
        type: TransactionType.income,
        amountMinor: 500000,
        accountId: 'acct-1',
        date: thisMonth,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-last-month',
        type: TransactionType.income,
        amountMinor: 200000,
        accountId: 'acct-1',
        date: lastMonth,
      ),
    );
    await tester.pumpAndSettle();

    // Also the Net card's value, since there's no expense this month.
    expect(find.text('৳5,000.00'), findsWidgets);

    await tester.tap(find.text('Last month'));
    await tester.pumpAndSettle();

    expect(find.text('৳2,000.00'), findsWidgets);
    expect(find.text('৳5,000.00'), findsNothing);

    await database.close();
  });

  testWidgets('lists categories highest spend first', (tester) async {
    final database = await pumpReports(tester);
    final categories = CategoryDao(database);
    final transactions = TransactionDao(database);

    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'cat-test-groceries',
        name: 'Groceries',
        type: CategoryType.expense,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-transport',
        type: TransactionType.expense,
        amountMinor: 5000,
        accountId: 'acct-1',
        categoryId: const Value('cat-transport'),
        date: thisMonth,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-groceries',
        type: TransactionType.expense,
        amountMinor: 30000,
        accountId: 'acct-1',
        categoryId: const Value('cat-test-groceries'),
        date: thisMonth,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spending by category'), findsOneWidget);
    final groceriesTop = tester.getTopLeft(find.text('Groceries')).dy;
    final transportTop = tester.getTopLeft(find.text('Transport')).dy;
    expect(groceriesTop, lessThan(transportTop));

    await database.close();
  });

  testWidgets('shows an active budget in Budget Performance', (tester) async {
    final database = await pumpReports(tester);
    final categories = CategoryDao(database);
    final budgets = BudgetDao(database);
    final transactions = TransactionDao(database);

    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'cat-groceries',
        name: 'Groceries',
        type: CategoryType.expense,
      ),
    );
    await budgets.insertOne(
      BudgetsCompanion.insert(
        id: 'budget-groceries',
        categoryId: 'cat-groceries',
        amountMinor: 100000, // ৳1,000
        period: BudgetPeriod.monthly,
        startDate: thisMonth,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-groceries',
        type: TransactionType.expense,
        amountMinor: 40000, // ৳400
        accountId: 'acct-1',
        categoryId: const Value('cat-groceries'),
        date: thisMonth,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Budget Performance'), findsOneWidget);
    // Also appears in "Spending by category" above, since the same category
    // has a matching expense this period.
    expect(find.text('Groceries'), findsNWidgets(2));
    expect(find.text('৳400.00 / ৳1,000.00'), findsOneWidget);
    expect(find.text('On track'), findsOneWidget);

    await database.close();
  });

  testWidgets('excludes an archived budget from Budget Performance', (
    tester,
  ) async {
    final database = await pumpReports(tester);
    final categories = CategoryDao(database);
    final budgets = BudgetDao(database);

    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'cat-groceries',
        name: 'Groceries',
        type: CategoryType.expense,
      ),
    );
    await budgets.insertOne(
      BudgetsCompanion.insert(
        id: 'budget-groceries',
        categoryId: 'cat-groceries',
        amountMinor: 100000,
        period: BudgetPeriod.monthly,
        startDate: thisMonth,
      ),
    );
    await budgets.updateStatus('budget-groceries', BudgetStatus.archived);
    await tester.pumpAndSettle();

    expect(find.text('Budget Performance'), findsNothing);

    await database.close();
  });

  testWidgets('shows an account with activity in Cash Flow by Account, '
      'omits one without', (tester) async {
    final database = await pumpReports(tester);
    final accounts = AccountDao(database);
    final transactions = TransactionDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-idle',
        name: 'Savings',
        type: AccountType.bank,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-groceries',
        type: TransactionType.expense,
        amountMinor: 40000, // ৳400
        accountId: 'acct-1',
        date: thisMonth,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cash Flow by Account'), findsOneWidget);
    expect(find.text('Main Bank'), findsOneWidget);
    expect(find.text('Savings'), findsNothing);
    // The Net card and the account's own row show the same net amount,
    // since this is the only account with activity.
    expect(find.text('-৳400.00'), findsNWidgets(2));

    await database.close();
  });
}
