import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Financial-correctness tests for the balance impact computation
/// ([TransactionDao.balanceImpactFor]).
///
/// The impact of a transaction on an account's balance is a core invariant
/// (docs/DATA_MODEL.md §45-§46):
/// * income    → +amount
/// * expense   → −amount
/// * transfer out (source)  → −amount
/// * transfer in (destination) → +amount
///
/// A transfer must net to zero across both accounts (source_change +
/// destination_change = 0). These tests pin that down for every combination.
void main() {
  group('balanceImpactFor', () {
    late AppDatabase database;
    late AccountDao accounts;
    late TransactionDao dao;

    setUp(() {
      database = AppDatabase.inMemory();
      accounts = AccountDao(database);
      dao = TransactionDao(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> seedAccount(String name) async {
      final id = 'acct-$name';
      await accounts.insertOne(
        FinancialAccountsCompanion.insert(id: id, name: name, type: AccountType.bank),
      );
      return id;
    }

    Future<void> add(
      String id,
      String accountId, {
      TransactionType type = TransactionType.expense,
      int amountMinor = 1000,
      String? destinationAccountId,
    }) async {
      await dao.insertOne(
        TransactionRow(
          id: id,
          type: type,
          amountMinor: amountMinor,
          currency: 'BDT',
          accountId: accountId,
          destinationAccountId: destinationAccountId,
          categoryId: null,
          date: DateTime(2026, 8, 10),
          description: '',
          createdAt: DateTime(2026, 8, 10),
          updatedAt: DateTime(2026, 8, 10),
        ).toCompanion(true),
      );
    }

    test('empty account has zero impact', () async {
      final account = await seedAccount('One');
      expect(await dao.balanceImpactFor(account), 0);
    });

    test('single income adds the full amount', () async {
      final account = await seedAccount('One');
      await add('i1', account, type: TransactionType.income, amountMinor: 50000);
      expect(await dao.balanceImpactFor(account), 50000);
    });

    test('single expense subtracts the full amount', () async {
      final account = await seedAccount('One');
      await add('e1', account, type: TransactionType.expense, amountMinor: 30000);
      expect(await dao.balanceImpactFor(account), -30000);
    });

    test('outgoing transfer subtracts from the source', () async {
      final source = await seedAccount('One');
      final destination = await seedAccount('Two');
      await add(
        't1',
        source,
        type: TransactionType.transfer,
        amountMinor: 250000,
        destinationAccountId: destination,
      );
      expect(await dao.balanceImpactFor(source), -250000);
    });

    test('incoming transfer adds to the destination', () async {
      final source = await seedAccount('One');
      final destination = await seedAccount('Two');
      await add(
        't1',
        source,
        type: TransactionType.transfer,
        amountMinor: 250000,
        destinationAccountId: destination,
      );
      expect(await dao.balanceImpactFor(destination), 250000);
    });

    test('a transfer nets to zero across both accounts', () async {
      final source = await seedAccount('One');
      final destination = await seedAccount('Two');
      await add(
        't1',
        source,
        type: TransactionType.transfer,
        amountMinor: 250000,
        destinationAccountId: destination,
      );

      final total = await dao.balanceImpactFor(source) +
          await dao.balanceImpactFor(destination);
      expect(total, 0);
    });

    test('income and expenses accumulate on the same account', () async {
      final account = await seedAccount('One');
      await add('i1', account, type: TransactionType.income, amountMinor: 1000000);
      await add('i2', account, type: TransactionType.income, amountMinor: 250000);
      await add('e1', account, type: TransactionType.expense, amountMinor: 300000);
      await add('e2', account, type: TransactionType.expense, amountMinor: 75000);

      // 1,000,000 + 250,000 − 300,000 − 75,000
      expect(await dao.balanceImpactFor(account), 875000);
    });

    test('an account on both sides of transfers is netted correctly', () async {
      final source = await seedAccount('One');
      final destination = await seedAccount('Two');
      final middle = await seedAccount('Three');

      // Middle sends to destination, and source sends to middle.
      await add(
        't1',
        middle,
        type: TransactionType.transfer,
        amountMinor: 100000,
        destinationAccountId: destination,
      );
      await add(
        't2',
        source,
        type: TransactionType.transfer,
        amountMinor: 40000,
        destinationAccountId: middle,
      );

      // Middle: −100,000 (out) + 40,000 (in) = −60,000
      expect(await dao.balanceImpactFor(middle), -60000);
    });

    test('full mixed scenario across income, expense, and transfer', () async {
      final savings = await seedAccount('One');
      final budget = await seedAccount('Two');

      await add('salary', savings, type: TransactionType.income, amountMinor: 1200000);
      await add('rent', budget, type: TransactionType.expense, amountMinor: 400000);
      await add(
        'to-budget',
        savings,
        type: TransactionType.transfer,
        amountMinor: 500000,
        destinationAccountId: budget,
      );
      await add('groceries', budget, type: TransactionType.expense, amountMinor: 150000);

      // Savings: +1,200,000 − 500,000 = 700,000
      expect(await dao.balanceImpactFor(savings), 700000);

      // Budget: −400,000 + 500,000 − 150,000 = −50,000
      expect(await dao.balanceImpactFor(budget), -50000);
    });
  });
}
