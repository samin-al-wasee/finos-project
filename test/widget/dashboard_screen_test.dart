import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/formatting/money.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/accounts/presentation/accounts_list_screen.dart';
import 'package:finos_app/features/accounts/presentation/account_form_screen.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:finos_app/features/budgets/presentation/budgets_list_screen.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:finos_app/features/investments/application/investment_controller.dart';
import 'package:finos_app/features/investments/data/investment_dao.dart';
import 'package:finos_app/features/investments/domain/investment_contribution_mode.dart';
import 'package:finos_app/features/investments/domain/investment_instrument_type.dart';
import 'package:finos_app/features/investments/presentation/investments_list_screen.dart';
import 'package:finos_app/features/reports/presentation/reports_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:finos_app/features/transactions/presentation/transactions_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppDatabase> pumpDashboard(WidgetTester tester) async {
    final database = AppDatabase.inMemory();
    // A tall viewport fits every summary card without scrolling, so cards
    // near the bottom (e.g. Recent Activity) are hit-testable directly.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
    // The expense is strictly later, so it — not the income — is
    // deterministically the "latest" transaction the Recent Activity card
    // previews.
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-income',
        type: TransactionType.income,
        amountMinor: 50000,
        accountId: 'acct-1',
        date: now.subtract(const Duration(minutes: 1)),
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
    // Appears on the Expenses card, the Spending-by-category card's top
    // entry, and the Recent Activity card's latest-transaction preview —
    // all the same expense, since it's the only one and it's also the
    // latest transaction.
    expect(find.text(formatMinorUnits(30000)), findsNWidgets(3));

    // Net cash flow.
    expect(
      find.text('Net this month ${formatMinorUnits(20000)}'),
      findsOneWidget,
    );

    // Accounts summary card — a count, not a per-account list.
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('1 account'), findsOneWidget);
    expect(find.text('Main Bank'), findsNothing);

    // Spending-by-category summary card shows the (only) top category, and
    // the Recent Activity card's latest-transaction preview shows the same
    // category name (not its raw description) since it's the categorized
    // expense.
    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('Food'), findsNWidgets(2));

    // Recent Activity summary card previews the latest transaction (the
    // categorized expense) rather than listing every transaction.
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('2 transactions this month'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);
    expect(find.text('Lunch'), findsNothing);

    await database.close();
  });

  testWidgets(
    'the spending-by-category card shows the highest-spend category and a '
    'count of the rest',
    (tester) async {
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
      // 'cat-food' and 'cat-transport' are built-in categories, seeded on
      // every fresh database — no need to insert them.

      final now = DateTime.now();
      // Distinct dates, with Food both the highest amount AND the latest
      // transaction, so the Recent Activity card's own latest-transaction
      // preview can never accidentally surface Transport or Uncategorized
      // and make this test flaky.
      await transactions.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-uncategorized',
          type: TransactionType.expense,
          amountMinor: 1000,
          accountId: 'acct-1',
          date: now.subtract(const Duration(minutes: 2)),
        ),
      );
      await transactions.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-transport',
          type: TransactionType.expense,
          amountMinor: 5000,
          accountId: 'acct-1',
          categoryId: Value('cat-transport'),
          date: now.subtract(const Duration(minutes: 1)),
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
      await tester.pumpAndSettle();

      // Highest spend (Food) is the one shown; Transport and Uncategorized
      // are folded into the "more categories" count instead of their own
      // rows — that per-category detail lives on Reports, not here. 'Food'
      // appears twice: once as the Spending card's top entry, once again as
      // the Recent Activity card's latest-transaction preview, since it's
      // both here.
      expect(find.text('Spending by category'), findsOneWidget);
      expect(find.text('Food'), findsNWidgets(2));
      expect(find.text('Transport'), findsNothing);
      expect(find.text('Uncategorized'), findsNothing);
      expect(find.text('and 2 more categories'), findsOneWidget);

      await database.close();
    },
  );

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

    // '.first': the Spending-by-category card's own "Food" (inside the
    // MergeSemantics below) renders before the Recent Activity card's latest-
    // transaction preview, which also happens to read "Food" here since this
    // expense is both the top category and the most recent transaction.
    final row = tester.getSemantics(
      find.ancestor(
        of: find.text('Food').first,
        matching: find.byType(MergeSemantics),
      ),
    );
    final label = row.getSemanticsData().label;
    expect(label, contains('Food'));
    expect(label, contains(formatMinorUnits(50000)));

    handle.dispose();
    await database.close();
  });

  testWidgets('tapping the Recent Activity card opens the Transactions tab', (
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

    await tester.tap(find.text('Recent activity'));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionsListScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('tapping the Accounts card opens the Accounts tab', (
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

    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountsListScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('tapping the Budgets card opens the Budgets tab', (tester) async {
    final database = await pumpDashboard(tester);
    final accounts = AccountDao(database);
    final budgets = BudgetDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await budgets.insertOne(
      BudgetsCompanion.insert(
        id: 'budget-1',
        categoryId: const Value('cat-food'),
        amountMinor: 100000,
        period: BudgetPeriod.monthly,
        startDate: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Budgets'));
    await tester.pumpAndSettle();

    expect(find.byType(BudgetsListScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('shows an Investments card once an active investment exists', (
    tester,
  ) async {
    final database = await pumpDashboard(tester);
    final accounts = AccountDao(database);
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(10000000),
      ),
    );

    expect(find.text('Investments'), findsNothing);

    final controller = InvestmentController(
      database,
      InvestmentDao(database),
      TransactionDao(database),
      accounts,
    );
    await controller.create(
      name: '1-year FDR',
      instrumentType: InvestmentInstrumentType.fdr,
      contributionMode: InvestmentContributionMode.lumpSum,
      amountMinor: 5000000,
      sourceAccountId: 'acct-bank',
      payoutAccountId: 'acct-bank',
      maturityDate: DateTime.now().add(const Duration(days: 365)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Investments'), findsOneWidget);
    expect(find.text('1 investment · ${formatMinorUnits(5000000)}'), findsOneWidget);

    await database.close();
  });

  testWidgets('tapping the Investments card opens the Investments screen', (
    tester,
  ) async {
    final database = await pumpDashboard(tester);
    final accounts = AccountDao(database);
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(10000000),
      ),
    );
    final controller = InvestmentController(
      database,
      InvestmentDao(database),
      TransactionDao(database),
      accounts,
    );
    await controller.create(
      name: '1-year FDR',
      instrumentType: InvestmentInstrumentType.fdr,
      contributionMode: InvestmentContributionMode.lumpSum,
      amountMinor: 5000000,
      sourceAccountId: 'acct-bank',
      payoutAccountId: 'acct-bank',
      maturityDate: DateTime.now().add(const Duration(days: 365)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Investments'));
    await tester.pumpAndSettle();

    expect(find.byType(InvestmentsListScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('tapping the Income card opens Reports', (tester) async {
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

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();

    expect(find.byType(ReportsScreen), findsOneWidget);

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
          categoryId: const Value('cat-food'),
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
