import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/savings_goals/application/savings_goal_controller.dart';
import 'package:finos_app/features/savings_goals/data/savings_goal_dao.dart';
import 'package:finos_app/features/savings_goals/domain/savings_goal_status.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Savings goal lifecycle rules: creation, contributions, withdrawals, and
/// deletion (docs/adr/011-savings-goals.md).
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late TransactionDao transactions;
  late SavingsGoalDao goals;
  late SavingsGoalController controller;

  setUp(() async {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    transactions = TransactionDao(database);
    goals = SavingsGoalDao(database);
    controller = SavingsGoalController(database, goals, transactions, accounts);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(10000000),
      ),
    );
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-closed',
        name: 'Closed Account',
        type: AccountType.bank,
        status: const Value(AccountStatus.archived),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('create', () {
    test('stores the goal and records no transaction', () async {
      final id = await controller.create(
        name: 'Emergency Fund',
        targetAmountMinor: 5000000,
        accountId: 'acct-bank',
        startDate: DateTime(2026, 1, 1),
        deadlineDate: DateTime(2027, 1, 1),
      );

      final row = await goals.getById(id);
      expect(row, isNotNull);
      expect(row!.name, 'Emergency Fund');
      expect(row.targetAmountMinor, 5000000);
      expect(row.accountId, 'acct-bank');
      expect(row.deadlineDate, DateTime(2027, 1, 1));
      expect(row.status, SavingsGoalStatus.active);
      expect(await transactions.getAll(), isEmpty);
    });

    test('deadline is optional', () async {
      final id = await controller.create(
        name: 'New Laptop',
        targetAmountMinor: 1500000,
        accountId: 'acct-bank',
      );

      final row = await goals.getById(id);
      expect(row!.deadlineDate, isNull);
    });

    test('rejects an empty name', () async {
      expect(
        () => controller.create(
          name: '  ',
          targetAmountMinor: 1000000,
          accountId: 'acct-bank',
        ),
        throwsArgumentError,
      );
    });

    test('rejects a zero or negative target amount', () async {
      expect(
        () => controller.create(
          name: 'Goal',
          targetAmountMinor: 0,
          accountId: 'acct-bank',
        ),
        throwsArgumentError,
      );
    });

    test('rejects a deadline before the start date', () async {
      expect(
        () => controller.create(
          name: 'Goal',
          targetAmountMinor: 1000000,
          accountId: 'acct-bank',
          startDate: DateTime(2026, 6, 1),
          deadlineDate: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an archived account', () async {
      expect(
        () => controller.create(
          name: 'Goal',
          targetAmountMinor: 1000000,
          accountId: 'acct-closed',
        ),
        throwsStateError,
      );
    });
  });

  group('contribute', () {
    Future<String> createGoal() => controller.create(
      name: 'Emergency Fund',
      targetAmountMinor: 1000000,
      accountId: 'acct-bank',
      startDate: DateTime(2026, 1, 1),
    );

    test('records a contribution transaction', () async {
      final id = await createGoal();

      final txnId = await controller.contribute(
        goalId: id,
        amountMinor: 300000,
        date: DateTime(2026, 2, 1),
      );

      final movements = await transactions.forSavingsGoal(id);
      expect(movements, hasLength(1));
      expect(movements.single.id, txnId);
      expect(movements.single.type, TransactionType.savingsContribution);
      expect(movements.single.amountMinor, 300000);
      expect(movements.single.accountId, 'acct-bank');

      final row = (await goals.getById(id))!;
      final progress = await controller.progressFor(row);
      expect(progress.contributedMinor, 300000);
      expect(progress.currentAmountMinor, 300000);
    });

    test('has no upper cap — saving beyond the target is ordinary', () async {
      final id = await createGoal();

      await controller.contribute(goalId: id, amountMinor: 1500000);

      final row = (await goals.getById(id))!;
      final progress = await controller.progressFor(row);
      expect(progress.currentAmountMinor, 1500000);
      expect(progress.isAchieved, isTrue);
    });

    test('rejects a zero or negative amount', () async {
      final id = await createGoal();
      expect(
        () => controller.contribute(goalId: id, amountMinor: 0),
        throwsArgumentError,
      );
    });

    test('rejects a contribution to an archived goal', () async {
      final id = await createGoal();
      await controller.archive(id);

      expect(
        () => controller.contribute(goalId: id, amountMinor: 100000),
        throwsStateError,
      );
    });

    test('throws for an unknown goal', () async {
      expect(
        () => controller.contribute(goalId: 'goal-ghost', amountMinor: 1000),
        throwsStateError,
      );
    });
  });

  group('withdraw', () {
    Future<String> createGoalWithSavings(int savedMinor) async {
      final id = await controller.create(
        name: 'Emergency Fund',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
        startDate: DateTime(2026, 1, 1),
      );
      await controller.contribute(goalId: id, amountMinor: savedMinor);
      return id;
    }

    test('records a withdrawal transaction and reduces the current amount', () async {
      final id = await createGoalWithSavings(500000);

      final txnId = await controller.withdraw(
        goalId: id,
        amountMinor: 200000,
        date: DateTime(2026, 3, 1),
      );

      final movements = await transactions.forSavingsGoal(id);
      final withdrawal = movements.firstWhere(
        (m) => m.type == TransactionType.savingsWithdrawal,
      );
      expect(withdrawal.id, txnId);
      expect(withdrawal.amountMinor, 200000);
      expect(withdrawal.accountId, 'acct-bank');

      final row = (await goals.getById(id))!;
      final progress = await controller.progressFor(row);
      expect(progress.withdrawnMinor, 200000);
      expect(progress.currentAmountMinor, 300000);
    });

    test('rejects a zero or negative amount', () async {
      final id = await createGoalWithSavings(500000);
      expect(
        () => controller.withdraw(goalId: id, amountMinor: 0),
        throwsArgumentError,
      );
    });

    test('rejects an amount larger than what is currently saved', () async {
      final id = await createGoalWithSavings(500000);

      expect(
        () => controller.withdraw(goalId: id, amountMinor: 600000),
        throwsArgumentError,
      );
    });

    test('rejects a withdrawal from an archived goal', () async {
      final id = await createGoalWithSavings(500000);
      await controller.archive(id);

      expect(
        () => controller.withdraw(goalId: id, amountMinor: 100000),
        throwsStateError,
      );
    });

    test('throws for an unknown goal', () async {
      expect(
        () => controller.withdraw(goalId: 'goal-ghost', amountMinor: 1000),
        throwsStateError,
      );
    });
  });

  group('update', () {
    test('changes name, target, deadline, and description', () async {
      final id = await controller.create(
        name: 'Emergency Fund',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
        startDate: DateTime(2026, 1, 1),
      );

      await controller.update(
        id: id,
        name: 'Bigger Emergency Fund',
        targetAmountMinor: 2000000,
        deadlineDate: DateTime(2027, 6, 1),
        description: 'Updated target',
      );

      final row = (await goals.getById(id))!;
      expect(row.name, 'Bigger Emergency Fund');
      expect(row.targetAmountMinor, 2000000);
      expect(row.deadlineDate, DateTime(2027, 6, 1));
      expect(row.description, 'Updated target');
    });

    test('rejects an empty name', () async {
      final id = await controller.create(
        name: 'Goal',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
      );

      expect(
        () => controller.update(id: id, name: '  ', targetAmountMinor: 1000000),
        throwsArgumentError,
      );
    });

    test('throws for an unknown goal', () async {
      expect(
        () => controller.update(
          id: 'goal-ghost',
          name: 'Goal',
          targetAmountMinor: 1000000,
        ),
        throwsStateError,
      );
    });
  });

  group('lifecycle', () {
    test('archive then restore', () async {
      final id = await controller.create(
        name: 'Goal',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
      );

      await controller.archive(id);
      expect((await goals.getById(id))!.status, SavingsGoalStatus.archived);

      await controller.restore(id);
      expect((await goals.getById(id))!.status, SavingsGoalStatus.active);
    });

    test('deletes a goal with no movements at all', () async {
      final id = await controller.create(
        name: 'Goal',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
      );

      await controller.delete(id);

      expect(await goals.getById(id), isNull);
    });

    test('refuses to delete a goal once a contribution is recorded', () async {
      final id = await controller.create(
        name: 'Goal',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
      );
      await controller.contribute(goalId: id, amountMinor: 100000);

      await expectLater(
        () => controller.delete(id),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('Archive it instead'),
          ),
        ),
      );

      expect(await goals.getById(id), isNotNull);
    });

    test('refuses to delete a goal once a withdrawal is recorded', () async {
      final id = await controller.create(
        name: 'Goal',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
      );
      await controller.contribute(goalId: id, amountMinor: 500000);
      await controller.withdraw(goalId: id, amountMinor: 100000);

      await expectLater(
        () => controller.delete(id),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('Archive it instead'),
          ),
        ),
      );

      expect(await goals.getById(id), isNotNull);
    });

    test('delete throws for an unknown goal', () async {
      expect(() => controller.delete('goal-ghost'), throwsStateError);
    });
  });

  group('progressFor', () {
    test('sums contributions and withdrawals', () async {
      final id = await controller.create(
        name: 'Goal',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
        startDate: DateTime(2026, 1, 1),
      );
      await controller.contribute(goalId: id, amountMinor: 400000);
      await controller.contribute(goalId: id, amountMinor: 300000);
      await controller.withdraw(goalId: id, amountMinor: 100000);

      final row = (await goals.getById(id))!;
      final progress = await controller.progressFor(row);

      expect(progress.contributedMinor, 700000);
      expect(progress.withdrawnMinor, 100000);
      expect(progress.currentAmountMinor, 600000);
      expect(progress.isAchieved, isFalse);
    });
  });
}
