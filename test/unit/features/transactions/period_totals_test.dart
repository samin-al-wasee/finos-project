import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the dashboard aggregation queries:
/// [TransactionDao.totalsForPeriod] and [TransactionDao.totalBalanceImpact].
///
/// `totalsForPeriod` sums income and expense in a half-open `[from, to)` range.
/// Transfers are excluded — they move money between accounts and are neither
/// income nor expense (docs/DATA_MODEL.md §17).
void main() {
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
      FinancialAccountsCompanion.insert(
        id: id,
        name: name,
        type: AccountType.bank,
      ),
    );
    return id;
  }

  Future<void> add(
    String id,
    String accountId, {
    required DateTime date,
    TransactionType type = TransactionType.expense,
    int amountMinor = 1000,
    String? destinationAccountId,
    String? categoryId,
  }) async {
    await dao.insertOne(
      TransactionRow(
        id: id,
        type: type,
        amountMinor: amountMinor,
        currency: 'BDT',
        accountId: accountId,
        destinationAccountId: destinationAccountId,
        categoryId: categoryId,
        date: date,
        description: '',
        createdAt: date,
        updatedAt: date,
      ).toCompanion(true),
    );
  }

  group('totalsForPeriod', () {
    final from = DateTime(2026, 8, 1);
    final to = DateTime(2026, 9, 1);

    test('empty period sums to zero', () async {
      final account = await seedAccount('One');
      await add('outside', account, date: DateTime(2026, 7, 15));

      final totals = await dao.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
    });

    test('income only sums income', () async {
      final account = await seedAccount('One');
      await add(
        'i1',
        account,
        date: DateTime(2026, 8, 10),
        type: TransactionType.income,
        amountMinor: 50000,
      );
      await add(
        'i2',
        account,
        date: DateTime(2026, 8, 20),
        type: TransactionType.income,
        amountMinor: 25000,
      );

      final totals = await dao.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 75000);
      expect(totals.expenseMinor, 0);
    });

    test('expense only sums expense', () async {
      final account = await seedAccount('One');
      await add('e1', account, date: DateTime(2026, 8, 5), amountMinor: 30000);
      await add('e2', account, date: DateTime(2026, 8, 15), amountMinor: 75000);

      final totals = await dao.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 105000);
    });

    test('transfers are excluded from income and expense', () async {
      final source = await seedAccount('One');
      final destination = await seedAccount('Two');
      await add(
        't1',
        source,
        date: DateTime(2026, 8, 12),
        type: TransactionType.transfer,
        amountMinor: 250000,
        destinationAccountId: destination,
      );

      final totals = await dao.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
    });

    test(
      'mixed scenario ignores transfers but sums income and expense',
      () async {
        final source = await seedAccount('One');
        final destination = await seedAccount('Two');
        await add(
          'salary',
          source,
          date: DateTime(2026, 8, 1),
          type: TransactionType.income,
          amountMinor: 1200000,
        );
        await add(
          'rent',
          destination,
          date: DateTime(2026, 8, 2),
          amountMinor: 400000,
        );
        await add(
          'to-destination',
          source,
          date: DateTime(2026, 8, 3),
          type: TransactionType.transfer,
          amountMinor: 500000,
          destinationAccountId: destination,
        );
        await add(
          'groceries',
          destination,
          date: DateTime(2026, 8, 4),
          amountMinor: 150000,
        );

        final totals = await dao.totalsForPeriod(from, to);
        expect(totals.incomeMinor, 1200000);
        expect(totals.expenseMinor, 550000);
      },
    );

    test('transactions outside the period are excluded', () async {
      final account = await seedAccount('One');
      await add(
        'before',
        account,
        date: DateTime(2026, 7, 31),
        type: TransactionType.income,
        amountMinor: 1000,
      );
      await add(
        'after',
        account,
        date: DateTime(2026, 9, 30),
        amountMinor: 1000,
      );

      final totals = await dao.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 0);
      expect(totals.expenseMinor, 0);
    });

    test('half-open boundary includes `from` and excludes `to`', () async {
      final account = await seedAccount('One');
      await add(
        'at-from',
        account,
        date: from,
        type: TransactionType.income,
        amountMinor: 1000,
      );
      await add(
        'at-to',
        account,
        date: to,
        type: TransactionType.income,
        amountMinor: 1000,
      );
      // One second before `to` — Drift stores dateTime at second precision,
      // so 23:59:59 of the last day is the latest representable in-period time.
      await add(
        'before-to',
        account,
        date: to.subtract(const Duration(seconds: 1)),
        type: TransactionType.income,
        amountMinor: 1000,
      );

      final totals = await dao.totalsForPeriod(from, to);
      expect(totals.incomeMinor, 2000);
      expect(totals.expenseMinor, 0);
    });

    test('netCashFlowMinor is income minus expense', () async {
      final account = await seedAccount('One');
      await add(
        'salary',
        account,
        date: DateTime(2026, 8, 1),
        type: TransactionType.income,
        amountMinor: 50000,
      );
      await add(
        'rent',
        account,
        date: DateTime(2026, 8, 2),
        amountMinor: 30000,
      );

      final positive = await dao.totalsForPeriod(from, to);
      expect(positive.netCashFlowMinor, 20000);
    });

    test('netCashFlowMinor is negative when spending exceeds income', () async {
      final account = await seedAccount('One');
      await add(
        'salary',
        account,
        date: DateTime(2026, 8, 1),
        type: TransactionType.income,
        amountMinor: 30000,
      );
      await add(
        'rent',
        account,
        date: DateTime(2026, 8, 2),
        amountMinor: 50000,
      );

      final negative = await dao.totalsForPeriod(from, to);
      expect(negative.netCashFlowMinor, -20000);
    });
  });

  group('totalBalanceImpact', () {
    test('empty table has zero impact', () async {
      expect(await dao.totalBalanceImpact(), 0);
    });

    test('income minus expense across all accounts', () async {
      final savings = await seedAccount('One');
      final budget = await seedAccount('Two');
      await add(
        'salary',
        savings,
        date: DateTime(2026, 8, 1),
        type: TransactionType.income,
        amountMinor: 1200000,
      );
      await add(
        'rent',
        budget,
        date: DateTime(2026, 8, 2),
        amountMinor: 400000,
      );
      await add(
        'groceries',
        budget,
        date: DateTime(2026, 8, 4),
        amountMinor: 150000,
      );

      // 1,200,000 − 400,000 − 150,000
      expect(await dao.totalBalanceImpact(), 650000);
    });

    test('transfers net to zero globally', () async {
      final source = await seedAccount('One');
      final destination = await seedAccount('Two');
      await add(
        't1',
        source,
        date: DateTime(2026, 8, 12),
        type: TransactionType.transfer,
        amountMinor: 250000,
        destinationAccountId: destination,
      );

      expect(await dao.totalBalanceImpact(), 0);
    });

    test('equals the sum of per-account impacts', () async {
      final savings = await seedAccount('One');
      final budget = await seedAccount('Two');

      await add(
        'salary',
        savings,
        date: DateTime(2026, 8, 1),
        type: TransactionType.income,
        amountMinor: 1200000,
      );
      await add(
        'rent',
        budget,
        date: DateTime(2026, 8, 2),
        amountMinor: 400000,
      );
      await add(
        'to-budget',
        savings,
        date: DateTime(2026, 8, 3),
        type: TransactionType.transfer,
        amountMinor: 500000,
        destinationAccountId: budget,
      );
      await add(
        'groceries',
        budget,
        date: DateTime(2026, 8, 4),
        amountMinor: 150000,
      );

      final perAccount =
          await dao.balanceImpactFor(savings) +
          await dao.balanceImpactFor(budget);
      expect(await dao.totalBalanceImpact(), perAccount);
    });
  });

  group('expenseTotalsByCategory', () {
    final from = DateTime(2026, 8, 1);
    final to = DateTime(2026, 9, 1);

    test('empty period returns an empty map', () async {
      final account = await seedAccount('One');
      await add('outside', account, date: DateTime(2026, 7, 15));

      expect(await dao.expenseTotalsByCategory(from, to), isEmpty);
    });

    test('sums expenses per category', () async {
      final account = await seedAccount('One');
      await add(
        'food-1',
        account,
        date: DateTime(2026, 8, 5),
        amountMinor: 30000,
        categoryId: 'cat-food',
      );
      await add(
        'food-2',
        account,
        date: DateTime(2026, 8, 15),
        amountMinor: 20000,
        categoryId: 'cat-food',
      );
      await add(
        'transport',
        account,
        date: DateTime(2026, 8, 10),
        amountMinor: 5000,
        categoryId: 'cat-transport',
      );

      final byCategory = await dao.expenseTotalsByCategory(from, to);
      expect(byCategory['cat-food'], 50000);
      expect(byCategory['cat-transport'], 5000);
    });

    test('an uncategorized expense is grouped under a null key', () async {
      final account = await seedAccount('One');
      await add('uncategorized', account, date: DateTime(2026, 8, 5));

      final byCategory = await dao.expenseTotalsByCategory(from, to);
      expect(byCategory[null], 1000);
    });

    test('income and transfers are excluded', () async {
      final source = await seedAccount('One');
      final destination = await seedAccount('Two');
      await add(
        'salary',
        source,
        date: DateTime(2026, 8, 1),
        type: TransactionType.income,
        amountMinor: 50000,
        categoryId: 'cat-food',
      );
      await add(
        'transfer',
        source,
        date: DateTime(2026, 8, 2),
        type: TransactionType.transfer,
        amountMinor: 20000,
        destinationAccountId: destination,
      );

      expect(await dao.expenseTotalsByCategory(from, to), isEmpty);
    });

    test('transactions outside the period are excluded', () async {
      final account = await seedAccount('One');
      await add(
        'before',
        account,
        date: DateTime(2026, 7, 31),
        amountMinor: 1000,
        categoryId: 'cat-food',
      );

      expect(await dao.expenseTotalsByCategory(from, to), isEmpty);
    });
  });
}
