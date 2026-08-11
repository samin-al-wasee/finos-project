import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/formatting/money.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/accounts/presentation/account_details_screen.dart';
import 'package:finos_app/features/accounts/presentation/account_form_screen.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
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
    // Appears on both the Expenses card and the "Spending by category" tile,
    // since the one expense is entirely in the 'Food' category.
    expect(find.text(formatMinorUnits(30000)), findsNWidgets(2));

    // Net cash flow.
    expect(
      find.text('Net this month ${formatMinorUnits(20000)}'),
      findsOneWidget,
    );

    // Account section.
    expect(find.text('Main Bank'), findsWidgets);

    // Recent transactions — category title 'Food' for the expense, and the
    // description 'Salary' for the uncategorized income.
    expect(find.text('Food'), findsWidgets);
    expect(find.text('Salary'), findsOneWidget);

    // Spending by category section is present.
    expect(find.text('Spending by category'), findsOneWidget);

    await database.close();
  });

  testWidgets('spending by category ranks categories by amount', (
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
    // 'cat-food' and 'cat-transport' are built-in categories, seeded on every
    // fresh database — no need to insert them.

    final now = DateTime.now();
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-transport',
        type: TransactionType.expense,
        amountMinor: 5000,
        accountId: 'acct-1',
        categoryId: Value('cat-transport'),
        date: now,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-food',
        type: TransactionType.expense,
        amountMinor: 30000,
        accountId: 'acct-1',
        categoryId: Value('cat-food'),
        date: now,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-uncategorized',
        type: TransactionType.expense,
        amountMinor: 1000,
        accountId: 'acct-1',
        date: now,
      ),
    );
    await tester.pumpAndSettle();

    // Highest spend first: Food, then Transport, then Uncategorized.
    final sectionTop = tester.getTopLeft(find.text('Spending by category'));
    final foodTop = tester.getTopLeft(find.text('Food').last);
    final transportTop = tester.getTopLeft(find.text('Transport'));
    final uncategorizedTop = tester.getTopLeft(find.text('Uncategorized'));
    expect(foodTop.dy, greaterThan(sectionTop.dy));
    expect(transportTop.dy, greaterThan(foodTop.dy));
    expect(uncategorizedTop.dy, greaterThan(transportTop.dy));

    await database.close();
  });

  testWidgets('no expenses hides the spending-by-category section', (
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

    expect(find.text('Spending by category'), findsNothing);

    await database.close();
  });

  testWidgets('a category-spending row narrates as one statement '
      '(docs/UI_DESIGN.md §43)', (tester) async {
    final handle = tester.ensureSemantics();
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
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-1',
        type: TransactionType.expense,
        amountMinor: 50000,
        accountId: 'acct-1',
        categoryId: Value('cat-1'),
        date: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester.getSemantics(
      find.ancestor(
        of: find.text('Food'),
        matching: find.byType(MergeSemantics),
      ),
    );
    final label = row.getSemanticsData().label;
    expect(label, contains('Food'));
    expect(label, contains(formatMinorUnits(50000)));

    handle.dispose();
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

  testWidgets('no spurious open-timeout error after an idle period', (
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

    // Idle longer than the 15s stream-open timeout. The in-memory database
    // opened immediately, so a healthy-but-quiet stream must stay silent
    // instead of surfacing "Opening the database is taking too long".
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();

    expect(find.text('Total Balance'), findsOneWidget);
    expect(find.textContaining('taking too long'), findsNothing);

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

  group('budget status', () {
    Future<AppDatabase> pumpWithBudget(
      WidgetTester tester, {
      required int limitMinor,
      required int spentMinor,
      BudgetStatus status = BudgetStatus.active,
    }) async {
      final database = await pumpDashboard(tester);
      final accounts = AccountDao(database);
      final budgets = BudgetDao(database);
      final transactions = TransactionDao(database);

      await accounts.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-1',
          name: 'Main Bank',
          type: AccountType.bank,
        ),
      );
      final now = DateTime.now();
      await budgets.insertOne(
        BudgetsCompanion.insert(
          id: 'budget-1',
          // Built in, seeded on every fresh database.
          categoryId: 'cat-food',
          amountMinor: limitMinor,
          period: BudgetPeriod.monthly,
          startDate: now,
          status: Value(status),
        ),
      );
      if (spentMinor > 0) {
        await transactions.insertOne(
          TransactionsCompanion.insert(
            id: 'tx-spend',
            type: TransactionType.expense,
            amountMinor: spentMinor,
            accountId: 'acct-1',
            categoryId: const Value('cat-food'),
            date: now,
          ),
        );
      }
      await tester.pumpAndSettle();
      return database;
    }

    testWidgets('no budgets hides the section', (tester) async {
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

      expect(find.text('Budgets'), findsNothing);

      await database.close();
    });

    testWidgets('an under-limit budget shows the amount remaining', (
      tester,
    ) async {
      final database = await pumpWithBudget(
        tester,
        limitMinor: 100000,
        spentMinor: 30000,
      );

      expect(find.text('Budgets'), findsOneWidget);
      expect(find.text('${formatMinorUnits(70000)} remaining'), findsOneWidget);
      expect(find.textContaining('over limit'), findsNothing);
      expect(find.textContaining('near limit'), findsNothing);

      await database.close();
    });

    testWidgets('a near-limit budget is called out by count', (tester) async {
      // 85% of the limit — above the 80% near-limit threshold.
      final database = await pumpWithBudget(
        tester,
        limitMinor: 100000,
        spentMinor: 85000,
      );

      expect(find.text('1 near limit'), findsOneWidget);

      await database.close();
    });

    testWidgets('an exceeded budget shows the amount over and its count', (
      tester,
    ) async {
      final database = await pumpWithBudget(
        tester,
        limitMinor: 100000,
        spentMinor: 150000,
      );

      expect(
        find.text('${formatMinorUnits(50000)} over budget'),
        findsOneWidget,
      );
      expect(find.text('1 over limit'), findsOneWidget);

      await database.close();
    });

    testWidgets('an archived budget is excluded from the summary', (
      tester,
    ) async {
      final database = await pumpWithBudget(
        tester,
        limitMinor: 100000,
        spentMinor: 150000,
        status: BudgetStatus.archived,
      );

      expect(find.text('Budgets'), findsNothing);

      await database.close();
    });
  });
}
