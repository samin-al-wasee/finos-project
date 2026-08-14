import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/savings_goals/application/savings_goal_controller.dart';
import 'package:finos_app/features/savings_goals/data/savings_goal_dao.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// How savings goals reach — and stay out of — the financial totals
/// (docs/adr/011-savings-goals.md), the same two pulling-in-opposite-
/// directions invariants `investment_balance_impact_test.dart` verifies for
/// investments:
///
/// * goal movements **do** change account balances — money really moves
/// * goal movements **never** touch income, expenses, or budgets — they are
///   balance-sheet events, not earning or spending
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late CategoryDao categories;
  late TransactionDao transactions;
  late SavingsGoalDao goals;
  late SavingsGoalController controller;

  setUp(() async {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    categories = CategoryDao(database);
    transactions = TransactionDao(database);
    goals = SavingsGoalDao(database);
    controller = SavingsGoalController(database, goals, transactions, accounts);

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

  Future<String> createGoal() => controller.create(
    name: 'Emergency Fund',
    targetAmountMinor: 5000000,
    accountId: 'acct-bank',
  );

  group('a contribution', () {
    test('reduces the linked account balance', () async {
      final id = await createGoal();
      await controller.contribute(goalId: id, amountMinor: 2000000);

      // ৳100,000 − ৳20,000
      expect(await balanceOf('acct-bank'), 8000000);
    });
  });

  group('a withdrawal', () {
    test('increases the linked account balance again', () async {
      final id = await createGoal();
      await controller.contribute(goalId: id, amountMinor: 2000000);
      await controller.withdraw(goalId: id, amountMinor: 500000);

      // ৳100,000 − ৳20,000 + ৳5,000
      expect(await balanceOf('acct-bank'), 8500000);
    });
  });

  group('portfolio total', () {
    test('a contribution reduces the total the user holds', () async {
      final id = await createGoal();
      await controller.contribute(goalId: id, amountMinor: 2000000);

      expect(await transactions.totalBalanceImpact(), -2000000);
    });

    test('a withdrawal increases the total the user holds', () async {
      final id = await createGoal();
      await controller.contribute(goalId: id, amountMinor: 2000000);
      await controller.withdraw(goalId: id, amountMinor: 2000000);

      expect(await transactions.totalBalanceImpact(), 0);
    });
  });

  group('exclusion from income and expenses', () {
    final from = DateTime(2026, 8, 1);
    final to = DateTime(2026, 9, 1);

    test('a contribution is not an expense', () async {
      final id = await createGoal();
      await controller.contribute(
        goalId: id,
        amountMinor: 2000000,
        date: DateTime(2026, 8, 5),
      );

      final totals = await transactions.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
    });

    test('a withdrawal is not income', () async {
      final id = await createGoal();
      await controller.contribute(goalId: id, amountMinor: 2000000);
      await controller.withdraw(
        goalId: id,
        amountMinor: 500000,
        date: DateTime(2026, 8, 10),
      );

      final totals = await transactions.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
    });
  });

  group('exclusion from budgets', () {
    test('goal movements never consume a budget', () async {
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

      final id = await createGoal();
      await controller.contribute(
        goalId: id,
        amountMinor: 2000000,
        date: DateTime(2026, 8, 5),
      );

      final spent = await transactions.expenseTotalForCategory(
        'test-food',
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
      );
      expect(spent, 0);
    });

    test('goal transactions carry no category at all', () async {
      final id = await createGoal();
      await controller.contribute(goalId: id, amountMinor: 2000000);
      await controller.withdraw(goalId: id, amountMinor: 500000);

      final rows = await transactions.getAll();
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row.categoryId, isNull);
        expect(row.savingsGoalId, id);
        expect(isSavingsGoalTransaction(row.type), isTrue);
      }
    });
  });

  group('storage values', () {
    test('the new types round-trip through the database', () async {
      final id = await createGoal();
      await controller.contribute(goalId: id, amountMinor: 2000000);

      final movements = await transactions.forSavingsGoal(id);
      expect(movements.single.type, TransactionType.savingsContribution);
    });

    test('the enum values are stored with underscores', () async {
      // Guards the same class of bug loan/investment balance-impact tests
      // guard: `name.toUpperCase()` would have produced SAVINGSCONTRIBUTION
      // and silently matched nothing in the balance queries.
      expect(
        const TransactionTypeConverter().toSql(
          TransactionType.savingsContribution,
        ),
        'SAVINGS_CONTRIBUTION',
      );
      expect(
        const TransactionTypeConverter().toSql(
          TransactionType.savingsWithdrawal,
        ),
        'SAVINGS_WITHDRAWAL',
      );

      final id = await createGoal();
      await controller.contribute(goalId: id, amountMinor: 2000000);

      final raw = await database
          .customSelect('SELECT type FROM transactions')
          .get();
      expect(raw.single.read<String>('type'), 'SAVINGS_CONTRIBUTION');
    });

    test('a withdrawal round-trips with an underscore-separated value', () async {
      final id = await createGoal();
      await controller.contribute(goalId: id, amountMinor: 2000000);
      await controller.withdraw(goalId: id, amountMinor: 500000);

      final movements = await transactions.forSavingsGoal(id);
      final withdrawal = movements.firstWhere(
        (m) => m.type == TransactionType.savingsWithdrawal,
      );

      final raw = await database
          .customSelect(
            'SELECT type FROM transactions WHERE id = ?',
            variables: [Variable(withdrawal.id)],
          )
          .getSingle();
      expect(raw.read<String>('type'), 'SAVINGS_WITHDRAWAL');
    });
  });
}
