import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/loans/application/loan_controller.dart';
import 'package:finos_app/features/loans/data/loan_dao.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// How loans reach — and stay out of — the financial totals (ADR-004).
///
/// This is the riskiest part of the loans feature: it changes calculations that
/// accounts, the dashboard, and budgets all depend on. Two invariants matter, and
/// they pull in opposite directions:
///
/// * loan movements **do** change account balances — money really moves
/// * loan movements **never** touch income, expenses, or budgets — they are
///   balance-sheet events, not earning or spending
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late CategoryDao categories;
  late TransactionDao transactions;
  late LoanDao loans;
  late LoanController controller;

  setUp(() async {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    categories = CategoryDao(database);
    transactions = TransactionDao(database);
    loans = LoanDao(database);
    controller = LoanController(database, loans, transactions, accounts);

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

  group('lending money out', () {
    test('reduces the account balance by the principal', () async {
      await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000, // ৳20,000
        disbursementAccountId: 'acct-bank',
      );

      // ৳100,000 − ৳20,000
      expect(await balanceOf('acct-bank'), 8000000);
    });

    test('a repayment received increases the balance again', () async {
      final loanId = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
      );

      await controller.recordRepayment(
        loanId: loanId,
        amountMinor: 500000, // ৳5,000 back
        accountId: 'acct-bank',
      );

      // ৳100,000 − ৳20,000 + ৳5,000
      expect(await balanceOf('acct-bank'), 8500000);
    });

    test('full repayment restores the original balance', () async {
      final loanId = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
      );
      await controller.recordRepayment(
        loanId: loanId,
        amountMinor: 2000000,
        accountId: 'acct-bank',
      );

      // Lending and being repaid in full leaves the user exactly where they
      // started — no income, no expense, no net change.
      expect(await balanceOf('acct-bank'), 10000000);
    });
  });

  group('borrowing money', () {
    test('increases the account balance by the principal', () async {
      await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 5000000, // ৳50,000
        disbursementAccountId: 'acct-bank',
      );

      expect(await balanceOf('acct-bank'), 15000000);
    });

    test('a repayment paid reduces the balance again', () async {
      final loanId = await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 5000000,
        disbursementAccountId: 'acct-bank',
      );

      await controller.recordRepayment(
        loanId: loanId,
        amountMinor: 1000000,
        accountId: 'acct-bank',
      );

      // ৳100,000 + ৳50,000 − ৳10,000
      expect(await balanceOf('acct-bank'), 14000000);
    });
  });

  group('a loan that pre-dates FinOS', () {
    test('moves no money when created without a disbursement account', () async {
      await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Old Bank Loan',
        principalMinor: 25000000,
      );

      // Opening state, exactly like an account's opening balance: the liability
      // exists but no cash moved today.
      expect(await balanceOf('acct-bank'), 10000000);
      expect(await transactions.getAll(), isEmpty);
    });

    test('but its repayments still move money', () async {
      final loanId = await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Old Bank Loan',
        principalMinor: 25000000,
      );

      await controller.recordRepayment(
        loanId: loanId,
        amountMinor: 500000,
        accountId: 'acct-bank',
      );

      expect(await balanceOf('acct-bank'), 9500000);
    });
  });

  group('portfolio total', () {
    test('lending reduces the total the user holds', () async {
      // Unlike a transfer, the other side of a loan is outside FinOS, so nothing
      // cancels it out. Omitting loans here would overstate the total.
      await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
      );

      expect(await transactions.totalBalanceImpact(), -2000000);
    });

    test('borrowing increases the total the user holds', () async {
      await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 5000000,
        disbursementAccountId: 'acct-bank',
      );

      expect(await transactions.totalBalanceImpact(), 5000000);
    });

    test('lending then being fully repaid nets to zero', () async {
      final loanId = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
      );
      await controller.recordRepayment(
        loanId: loanId,
        amountMinor: 2000000,
        accountId: 'acct-bank',
      );

      expect(await transactions.totalBalanceImpact(), 0);
    });

    test('a transfer still nets to zero alongside loan movements', () async {
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
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 5000000,
        disbursementAccountId: 'acct-bank',
      );

      // Only the loan shows up in the total; the transfer contributes nothing.
      expect(await transactions.totalBalanceImpact(), 5000000);
    });
  });

  group('exclusion from income and expenses', () {
    final from = DateTime(2026, 8, 1);
    final to = DateTime(2026, 9, 1);

    test('borrowing is not income', () async {
      await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 5000000,
        disbursementAccountId: 'acct-bank',
        startDate: DateTime(2026, 8, 5),
      );

      final totals = await transactions.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
      expect(totals.netCashFlowMinor, 0);
    });

    test('lending is not an expense', () async {
      await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
        startDate: DateTime(2026, 8, 5),
      );

      final totals = await transactions.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
    });

    test('repayments are neither income nor expense', () async {
      final borrowed = await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 5000000,
        disbursementAccountId: 'acct-bank',
        startDate: DateTime(2026, 8, 2),
      );
      final lent = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
        startDate: DateTime(2026, 8, 3),
      );

      await controller.recordRepayment(
        loanId: borrowed,
        amountMinor: 400000,
        accountId: 'acct-bank',
        date: DateTime(2026, 8, 10),
      );
      await controller.recordRepayment(
        loanId: lent,
        amountMinor: 300000,
        accountId: 'acct-bank',
        date: DateTime(2026, 8, 11),
      );

      final totals = await transactions.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
    });

    test(
      'real income and expenses are still counted alongside loans',
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
          direction: LoanDirection.borrowed,
          name: 'Bank Loan',
          principalMinor: 5000000,
          disbursementAccountId: 'acct-bank',
          startDate: DateTime(2026, 8, 3),
        );

        final totals = await transactions.totalsForPeriod(from, to);
        expect(totals.incomeMinor, 8000000);
        expect(totals.expenseMinor, 150000);
      },
    );
  });

  group('exclusion from budgets', () {
    test('loan movements never consume a budget', () async {
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
          categoryId: 'test-food',
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 8),
        ),
      );

      final loanId = await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 5000000,
        disbursementAccountId: 'acct-bank',
        startDate: DateTime(2026, 8, 3),
      );
      await controller.recordRepayment(
        loanId: loanId,
        amountMinor: 900000,
        accountId: 'acct-bank',
        date: DateTime(2026, 8, 10),
      );

      // A repayment is a large outflow, but it is not spending, so the Food
      // budget must be untouched.
      final spent = await transactions.expenseTotalForCategory(
        'test-food',
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
      );
      expect(spent, 0);
    });

    test('loan transactions carry no category at all', () async {
      final loanId = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
      );
      await controller.recordRepayment(
        loanId: loanId,
        amountMinor: 100000,
        accountId: 'acct-bank',
      );

      final rows = await transactions.getAll();
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row.categoryId, isNull);
        expect(row.loanId, loanId);
        expect(isLoanTransaction(row.type), isTrue);
      }
    });
  });

  group('storage values', () {
    test('the new types round-trip through the database', () async {
      final lent = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
      );
      final borrowed = await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 5000000,
        disbursementAccountId: 'acct-bank',
      );

      final lentMovements = await transactions.forLoan(lent);
      expect(lentMovements.single.type, TransactionType.loanPayment);

      final borrowedMovements = await transactions.forLoan(borrowed);
      expect(borrowedMovements.single.type, TransactionType.loanReceipt);
    });

    test('the enum values are stored with underscores', () async {
      // Guards the bug the converter change removed: `name.toUpperCase()` would
      // have produced LOANRECEIPT and silently matched nothing in the balance
      // queries.
      expect(
        const TransactionTypeConverter().toSql(TransactionType.loanReceipt),
        'LOAN_RECEIPT',
      );
      expect(
        const TransactionTypeConverter().toSql(TransactionType.loanPayment),
        'LOAN_PAYMENT',
      );

      await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 5000000,
        disbursementAccountId: 'acct-bank',
      );
      final raw = await database
          .customSelect('SELECT type FROM transactions')
          .get();
      expect(raw.single.read<String>('type'), 'LOAN_RECEIPT');
    });
  });
}
