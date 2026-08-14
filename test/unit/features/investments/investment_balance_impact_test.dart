import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/investments/application/investment_controller.dart';
import 'package:finos_app/features/investments/data/investment_dao.dart';
import 'package:finos_app/features/investments/domain/investment_contribution_mode.dart';
import 'package:finos_app/features/investments/domain/investment_instrument_type.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// How investments reach — and stay out of — the financial totals
/// (docs/adr/009-investment-accounting.md), the same two pulling-in-opposite-
/// directions invariants `loan_balance_impact_test.dart` verifies for loans:
///
/// * investment movements **do** change account balances — money really moves
/// * investment movements **never** touch income, expenses, or budgets — they
///   are balance-sheet events, not earning or spending
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late CategoryDao categories;
  late TransactionDao transactions;
  late InvestmentDao investments;
  late InvestmentController controller;

  setUp(() async {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    categories = CategoryDao(database);
    transactions = TransactionDao(database);
    investments = InvestmentDao(database);
    controller = InvestmentController(
      database,
      investments,
      transactions,
      accounts,
    );

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(10000000), // ৳100,000
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  /// Live balance of an account: opening balance plus every movement.
  Future<int> balanceOf(String accountId) async {
    final account = await accounts.getById(accountId);
    return account!.openingBalanceMinor +
        await transactions.balanceImpactFor(accountId);
  }

  group('a lump-sum contribution', () {
    test('reduces the source account balance by the principal', () async {
      await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000, // ৳20,000
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );

      // ৳100,000 − ৳20,000
      expect(await balanceOf('acct-bank'), 8000000);
    });

    test('a payout increases the payout account balance again', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );

      await controller.confirmNextPayout(
        id,
        amountMinor: 2200000, // principal + profit
        date: DateTime(2027, 1, 1),
      );

      // ৳100,000 − ৳20,000 + ৳22,000
      expect(await balanceOf('acct-bank'), 10200000);
    });

    test('a payout to a different account only affects that account', () async {
      await accounts.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-cash',
          name: 'Cash',
          type: AccountType.cash,
        ),
      );
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-cash',
        maturityDate: DateTime(2027, 1, 1),
      );

      await controller.confirmNextPayout(
        id,
        amountMinor: 2200000,
        date: DateTime(2027, 1, 1),
      );

      expect(await balanceOf('acct-bank'), 8000000); // unchanged since funding
      expect(await balanceOf('acct-cash'), 2200000);
    });
  });

  group('an early withdrawal', () {
    test(
      'increases the payout account balance again, like a payout',
      () async {
        final id = await controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 2000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime(2027, 1, 1),
        );

        await controller.confirmWithdrawal(id, amountMinor: 500000);

        // ৳100,000 − ৳20,000 + ৳5,000
        expect(await balanceOf('acct-bank'), 8500000);
      },
    );

    test('to a different account only affects that account', () async {
      await accounts.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-cash',
          name: 'Cash',
          type: AccountType.cash,
        ),
      );
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-cash',
        maturityDate: DateTime(2027, 1, 1),
      );

      await controller.confirmWithdrawal(id, amountMinor: 500000);

      expect(await balanceOf('acct-bank'), 8000000); // unchanged since funding
      expect(await balanceOf('acct-cash'), 500000);
    });
  });

  group('a recurring contribution (DPS)', () {
    test('each confirmed installment reduces the source balance', () async {
      final id = await controller.create(
        name: 'DPS',
        instrumentType: InvestmentInstrumentType.dps,
        contributionMode: InvestmentContributionMode.recurring,
        amountMinor: 500000, // ৳5,000
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        startDate: DateTime(2026, 1, 1),
        maturityDate: DateTime(2029, 1, 1),
      );

      await controller.confirmNextContribution(id);
      await controller.confirmNextContribution(id);

      // ৳100,000 − ৳5,000 − ৳5,000
      expect(await balanceOf('acct-bank'), 9000000);
    });
  });

  group('portfolio total', () {
    test('a contribution reduces the total the user holds', () async {
      // Unlike a transfer, the other side is outside FinOS, so nothing
      // cancels it out. Omitting investments here would overstate the total.
      await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );

      expect(await transactions.totalBalanceImpact(), -2000000);
    });

    test('a payout increases the total the user holds', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );
      await controller.confirmNextPayout(
        id,
        amountMinor: 2000000,
        date: DateTime(2027, 1, 1),
      );

      expect(await transactions.totalBalanceImpact(), 0);
    });

    test('a withdrawal increases the total the user holds', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );
      await controller.confirmWithdrawal(id, amountMinor: 2000000);

      expect(await transactions.totalBalanceImpact(), 0);
    });

    test(
      'a transfer still nets to zero alongside investment movements',
      () async {
        await accounts.insertOne(
          FinancialAccountsCompanion.insert(
            id: 'acct-cash',
            name: 'Cash',
            type: AccountType.cash,
          ),
        );
        await transactions.insertOne(
          TransactionsCompanion.insert(
            id: 'tx-transfer',
            type: TransactionType.transfer,
            amountMinor: 300000,
            accountId: 'acct-bank',
            destinationAccountId: const Value('acct-cash'),
            date: DateTime(2026, 8, 5),
          ),
        );
        await controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 5000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime(2027, 1, 1),
        );

        // Only the investment shows up in the total; the transfer contributes
        // nothing.
        expect(await transactions.totalBalanceImpact(), -5000000);
      },
    );
  });

  group('exclusion from income and expenses', () {
    final from = DateTime(2026, 8, 1);
    final to = DateTime(2026, 9, 1);

    test('a contribution is not an expense', () async {
      await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        startDate: DateTime(2026, 8, 5),
        maturityDate: DateTime(2027, 1, 1),
      );

      final totals = await transactions.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
    });

    test('a payout is not income', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        startDate: DateTime(2026, 1, 1),
        maturityDate: DateTime(2026, 8, 10),
      );
      await controller.confirmNextPayout(
        id,
        amountMinor: 2200000,
        date: DateTime(2026, 8, 10),
      );

      final totals = await transactions.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
    });

    test('a withdrawal is not income', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        startDate: DateTime(2026, 1, 1),
        maturityDate: DateTime(2027, 1, 1),
      );
      await controller.confirmWithdrawal(
        id,
        amountMinor: 500000,
        date: DateTime(2026, 8, 10),
      );

      final totals = await transactions.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
    });

    test(
      'real income and expenses are still counted alongside investments',
      () async {
        await transactions.insertOne(
          TransactionsCompanion.insert(
            id: 'tx-salary',
            type: TransactionType.income,
            amountMinor: 8000000,
            accountId: 'acct-bank',
            date: DateTime(2026, 8, 1),
          ),
        );
        await transactions.insertOne(
          TransactionsCompanion.insert(
            id: 'tx-food',
            type: TransactionType.expense,
            amountMinor: 150000,
            accountId: 'acct-bank',
            date: DateTime(2026, 8, 2),
          ),
        );
        await controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 5000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          startDate: DateTime(2026, 8, 3),
          maturityDate: DateTime(2027, 1, 1),
        );

        final totals = await transactions.totalsForPeriod(from, to);
        expect(totals.incomeMinor, 8000000);
        expect(totals.expenseMinor, 150000);
      },
    );
  });

  group('exclusion from budgets', () {
    test('investment movements never consume a budget', () async {
      await categories.insertOne(
        CategoriesCompanion.insert(
          id: 'test-food',
          name: 'Food',
          type: CategoryType.expense,
        ),
      );
      await BudgetDao(database).insertOne(
        BudgetsCompanion.insert(
          id: 'budget-food',
          categoryId: const Value('test-food'),
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 8),
        ),
      );

      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 5000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        startDate: DateTime(2026, 8, 3),
        maturityDate: DateTime(2026, 8, 20),
      );
      await controller.confirmNextPayout(
        id,
        amountMinor: 5500000,
        date: DateTime(2026, 8, 20),
      );

      // A payout is a large inflow, but it is not income, so the Food budget
      // (which only tracks expenses) must be untouched.
      final spent = await transactions.expenseTotalForCategory(
        'test-food',
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
      );
      expect(spent, 0);
    });

    test('investment transactions carry no category at all', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );
      await controller.confirmNextPayout(
        id,
        amountMinor: 100000,
        date: DateTime(2026, 6, 1),
      );

      final rows = await transactions.getAll();
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row.categoryId, isNull);
        expect(row.investmentId, id);
        expect(isInvestmentTransaction(row.type), isTrue);
      }
    });
  });

  group('storage values', () {
    test('the new types round-trip through the database', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );

      final movements = await transactions.forInvestment(id);
      expect(movements.single.type, TransactionType.investmentContribution);
    });

    test('the enum values are stored with underscores', () async {
      // Guards the same class of bug loan_balance_impact_test.dart guards:
      // `name.toUpperCase()` would have produced INVESTMENTCONTRIBUTION and
      // silently matched nothing in the balance queries.
      expect(
        const TransactionTypeConverter().toSql(
          TransactionType.investmentContribution,
        ),
        'INVESTMENT_CONTRIBUTION',
      );
      expect(
        const TransactionTypeConverter().toSql(
          TransactionType.investmentPayout,
        ),
        'INVESTMENT_PAYOUT',
      );
      expect(
        const TransactionTypeConverter().toSql(
          TransactionType.investmentWithdrawal,
        ),
        'INVESTMENT_WITHDRAWAL',
      );

      await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );
      final raw = await database
          .customSelect('SELECT type FROM transactions')
          .get();
      expect(raw.single.read<String>('type'), 'INVESTMENT_CONTRIBUTION');
    });

    test('a withdrawal round-trips with an underscore-separated value', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );
      await controller.confirmWithdrawal(id, amountMinor: 500000);

      final movements = await transactions.forInvestment(id);
      final withdrawal = movements.firstWhere(
        (m) => m.type == TransactionType.investmentWithdrawal,
      );
      expect(withdrawal.type, TransactionType.investmentWithdrawal);

      final raw = await database
          .customSelect(
            'SELECT type FROM transactions WHERE id = ?',
            variables: [Variable(withdrawal.id)],
          )
          .getSingle();
      expect(raw.read<String>('type'), 'INVESTMENT_WITHDRAWAL');
    });
  });
}
