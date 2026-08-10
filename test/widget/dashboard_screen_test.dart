import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/formatting/money.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/accounts/presentation/account_details_screen.dart';
import 'package:finos_app/features/accounts/presentation/account_form_screen.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:finos_app/features/transactions/presentation/transaction_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppDatabase> pumpDashboard(WidgetTester tester) async {
    final database = AppDatabase.inMemory();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  testWidgets('shows an empty state when there are no accounts', (
    tester,
  ) async {
    final database = await pumpDashboard(tester);

    expect(find.text('No accounts yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add account'), findsOneWidget);

    await database.close();
  });

  testWidgets('empty-state add button opens the account form', (tester) async {
    final database = await pumpDashboard(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountFormScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('renders total balance, income, expenses, and account', (
    tester,
  ) async {
    final database = await pumpDashboard(tester);
    final accounts = AccountDao(database);
    final categories = CategoryDao(database);
    final transactions = TransactionDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'cat-1',
        name: 'Food',
        type: CategoryType.expense,
      ),
    );

    final now = DateTime.now();
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-income',
        type: TransactionType.income,
        amountMinor: 50000,
        accountId: 'acct-1',
        date: now,
        description: Value('Salary'),
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-expense',
        type: TransactionType.expense,
        amountMinor: 30000,
        accountId: 'acct-1',
        categoryId: Value('cat-1'),
        date: now,
        description: Value('Lunch'),
      ),
    );

    // Let the stream providers pick up the new data.
    await tester.pumpAndSettle();

    // Total balance: +50,000 − 30,000 = 20,000
    expect(find.text('Total Balance'), findsOneWidget);
    expect(find.byKey(const ValueKey('totalBalance')), findsOneWidget);
    expect(find.text(formatMinorUnits(20000)), findsWidgets);

    // Income and expense cards.
    expect(find.text('Income'), findsOneWidget);
    expect(find.text(formatMinorUnits(50000)), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text(formatMinorUnits(30000)), findsOneWidget);

    // Net cash flow.
    expect(
      find.text('Net this month ${formatMinorUnits(20000)}'),
      findsOneWidget,
    );

    // Account section.
    expect(find.text('Main Bank'), findsWidgets);

    // Recent transactions — category title 'Food' for the expense, and the
    // description 'Salary' for the uncategorized income.
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);

    await database.close();
  });

  testWidgets('tapping a recent transaction opens the edit form', (
    tester,
  ) async {
    final database = await pumpDashboard(tester);
    final accounts = AccountDao(database);
    final transactions = TransactionDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-1',
        type: TransactionType.expense,
        amountMinor: 50000,
        accountId: 'acct-1',
        date: DateTime.now(),
        description: Value('Lunch'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionFormScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Edit transaction'), findsOneWidget);

    await database.close();
  });

  testWidgets('tapping an account navigates to the account details screen', (
    tester,
  ) async {
    final database = await pumpDashboard(tester);
    final accounts = AccountDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Main Bank').first);
    await tester.pumpAndSettle();

    expect(find.byType(AccountDetailsScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('accounts but no transactions shows zero totals and no crash', (
    tester,
  ) async {
    final database = await pumpDashboard(tester);
    final accounts = AccountDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total Balance'), findsOneWidget);
    // No transactions — recent list shows the empty hint.
    expect(find.text('No transactions yet'), findsOneWidget);
    // Totals are zero.
    expect(find.text(formatMinorUnits(0)), findsWidgets);

    await database.close();
  });
}
