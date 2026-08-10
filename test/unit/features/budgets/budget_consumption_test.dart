import 'package:drift/drift.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [TransactionDao.expenseTotalForCategory] — the budget-consumption
/// rule (docs/DATA_MODEL.md §24).
///
/// Only expenses in the budget's own category, inside the half-open window,
/// count towards a budget. Income is not spending, and a transfer moves the
/// user's own money between accounts, so neither may consume a budget
/// (docs/DATA_MODEL.md §17).
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late CategoryDao categories;
  late TransactionDao dao;

  final from = DateTime(2026, 8, 1);
  final to = DateTime(2026, 9, 1);

  setUp(() async {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    categories = CategoryDao(database);
    dao = TransactionDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-main',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-cash',
        name: 'Cash',
        type: AccountType.cash,
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-food',
        name: 'Food',
        type: CategoryType.expense,
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-transport',
        name: 'Transport',
        type: CategoryType.expense,
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-salary',
        name: 'Salary',
        type: CategoryType.income,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> add(
    String id, {
    required DateTime date,
    TransactionType type = TransactionType.expense,
    int amountMinor = 100000,
    String? categoryId = 'test-food',
    String accountId = 'acct-main',
    String? destinationAccountId,
  }) async {
    await dao.insertOne(
      TransactionsCompanion.insert(
        id: id,
        type: type,
        amountMinor: amountMinor,
        accountId: accountId,
        destinationAccountId: Value(destinationAccountId),
        categoryId: Value(categoryId),
        date: date,
      ),
    );
  }

  group('expenseTotalForCategory', () {
    test('is zero when the category has no transactions', () async {
      expect(await dao.expenseTotalForCategory('test-food', from, to), 0);
    });

    test('sums expenses in the category', () async {
      // The worked example from docs/DATA_MODEL.md §24: 2,000 + 1,500 + 1,200.
      await add('tx-1', date: DateTime(2026, 8, 3), amountMinor: 200000);
      await add('tx-2', date: DateTime(2026, 8, 12), amountMinor: 150000);
      await add('tx-3', date: DateTime(2026, 8, 25), amountMinor: 120000);

      expect(await dao.expenseTotalForCategory('test-food', from, to), 470000);
    });

    test('ignores expenses in other categories', () async {
      await add('tx-food', date: DateTime(2026, 8, 5), amountMinor: 100000);
      await add(
        'tx-transport',
        date: DateTime(2026, 8, 6),
        amountMinor: 300000,
        categoryId: 'test-transport',
      );

      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);
    });

    test('ignores uncategorised expenses', () async {
      await add('tx-food', date: DateTime(2026, 8, 5), amountMinor: 100000);
      await add(
        'tx-none',
        date: DateTime(2026, 8, 6),
        amountMinor: 500000,
        categoryId: null,
      );

      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);
    });

    test('excludes income even in a matching category', () async {
      await add(
        'tx-income',
        date: DateTime(2026, 8, 5),
        type: TransactionType.income,
        amountMinor: 900000,
        categoryId: 'test-salary',
      );

      expect(await dao.expenseTotalForCategory('test-salary', from, to), 0);
    });

    test('excludes transfers', () async {
      // Transfers always carry a null category, and the query filters on type
      // as well — belt and braces, because a transfer must never consume a
      // budget (docs/DATA_MODEL.md §17).
      await add(
        'tx-transfer',
        date: DateTime(2026, 8, 5),
        type: TransactionType.transfer,
        amountMinor: 500000,
        categoryId: null,
        destinationAccountId: 'acct-cash',
      );
      await add('tx-food', date: DateTime(2026, 8, 6), amountMinor: 100000);

      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);
    });

    test('counts spending from every account', () async {
      await add('tx-bank', date: DateTime(2026, 8, 5), amountMinor: 100000);
      await add(
        'tx-cash',
        date: DateTime(2026, 8, 6),
        amountMinor: 250000,
        accountId: 'acct-cash',
      );

      expect(await dao.expenseTotalForCategory('test-food', from, to), 350000);
    });
  });

  group('window boundaries', () {
    test('includes the first moment of the window', () async {
      await add('tx-first', date: DateTime(2026, 8, 1), amountMinor: 100000);

      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);
    });

    test('includes the last day of the window', () async {
      await add(
        'tx-last',
        date: DateTime(2026, 8, 31, 23, 59, 59),
        amountMinor: 100000,
      );

      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);
    });

    test('excludes the upper bound itself', () async {
      // Half-open range: a September 1st expense belongs to September's budget.
      await add('tx-next', date: DateTime(2026, 9, 1), amountMinor: 100000);

      expect(await dao.expenseTotalForCategory('test-food', from, to), 0);
    });

    test('excludes spending before the window', () async {
      await add('tx-prev', date: DateTime(2026, 7, 31), amountMinor: 100000);

      expect(await dao.expenseTotalForCategory('test-food', from, to), 0);
    });

    test('a deleted expense stops counting towards the budget', () async {
      await add('tx-food', date: DateTime(2026, 8, 5), amountMinor: 100000);
      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);

      await dao.deleteOne('tx-food');
      expect(await dao.expenseTotalForCategory('test-food', from, to), 0);
    });
  });
}
