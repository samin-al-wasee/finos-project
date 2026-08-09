import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/transactions/application/transaction_controller.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransactionController', () {
    late AppDatabase database;
    late AccountDao accounts;
    late CategoryDao categories;
    late TransactionDao dao;
    late TransactionController controller;

    setUp(() {
      database = AppDatabase.inMemory();
      accounts = AccountDao(database);
      categories = CategoryDao(database);
      dao = TransactionDao(database);
      controller = TransactionController(dao, accounts, categories);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> seedAccount(
      String name, {
      AccountStatus status = AccountStatus.active,
    }) async {
      final id = 'acct-$name';
      await accounts.insertOne(
        FinancialAccountsCompanion.insert(
          id: id,
          name: name,
          type: AccountType.bank,
          status: Value(status),
        ),
      );
      return id;
    }

    Future<String> seedCategory(
      String name, {
      CategoryType type = CategoryType.expense,
      CategoryStatus status = CategoryStatus.active,
    }) async {
      final id = 'cat-$name';
      await categories.insertOne(
        CategoriesCompanion.insert(
          id: id,
          name: name,
          type: type,
          status: Value(status),
        ),
      );
      return id;
    }

    test('create generates a stable id and applies the given values', () async {
      final source = await seedAccount('One');

      final id = await controller.create(
        type: TransactionType.expense,
        amountMinor: 50000,
        accountId: source,
        categoryId: await seedCategory('Food'),
        description: 'Lunch',
      );

      final row = await controller.getById(id);
      expect(row, isNotNull);
      expect(row!.id, id);
      expect(row.type, TransactionType.expense);
      expect(row.amountMinor, 50000);
      expect(row.accountId, source);
      expect(row.categoryId, isNotNull);
      expect(row.description, 'Lunch');
      expect(row.date, isNotNull);
    });

    test('create succeeds for income and transfer', () async {
      final source = await seedAccount('One');
      final destination = await seedAccount('Two');

      final incomeId = await controller.create(
        type: TransactionType.income,
        amountMinor: 100000,
        accountId: source,
      );
      expect(await controller.getById(incomeId), isNotNull);

      final transferId = await controller.create(
        type: TransactionType.transfer,
        amountMinor: 200000,
        accountId: source,
        destinationAccountId: destination,
      );
      final transfer = await controller.getById(transferId);
      expect(transfer, isNotNull);
      expect(transfer!.destinationAccountId, destination);
      expect(transfer.categoryId, isNull);
    });

    test('generates unique ids across creates', () async {
      final source = await seedAccount('One');
      final id1 = await controller.create(
        type: TransactionType.expense,
        amountMinor: 10,
        accountId: source,
      );
      final id2 = await controller.create(
        type: TransactionType.expense,
        amountMinor: 20,
        accountId: source,
      );
      expect(id1, isNot(id2));
    });

    group('create validation', () {
      test('rejects a non-positive amount', () async {
        final source = await seedAccount('One');
        expect(
          () => controller.create(
            type: TransactionType.expense,
            amountMinor: 0,
            accountId: source,
          ),
          throwsArgumentError,
        );
      });

      test('rejects a missing account', () async {
        expect(
          () => controller.create(
            type: TransactionType.expense,
            amountMinor: 100,
            accountId: 'acct-missing',
          ),
          throwsStateError,
        );
      });

      test('rejects an archived account', () async {
        final source = await seedAccount(
          'Archived',
          status: AccountStatus.archived,
        );
        expect(
          () => controller.create(
            type: TransactionType.expense,
            amountMinor: 100,
            accountId: source,
          ),
          throwsStateError,
        );
      });

      test('rejects a transfer without a destination', () async {
        final source = await seedAccount('One');
        expect(
          () => controller.create(
            type: TransactionType.transfer,
            amountMinor: 100,
            accountId: source,
          ),
          throwsArgumentError,
        );
      });

      test('rejects a transfer to the source account', () async {
        final source = await seedAccount('One');
        expect(
          () => controller.create(
            type: TransactionType.transfer,
            amountMinor: 100,
            accountId: source,
            destinationAccountId: source,
          ),
          throwsArgumentError,
        );
      });

      test('rejects a transfer with a missing destination', () async {
        final source = await seedAccount('One');
        expect(
          () => controller.create(
            type: TransactionType.transfer,
            amountMinor: 100,
            accountId: source,
            destinationAccountId: 'acct-missing',
          ),
          throwsStateError,
        );
      });

      test('rejects a transfer with a category', () async {
        final source = await seedAccount('One');
        final destination = await seedAccount('Two');
        final categoryId = await seedCategory('Food');
        expect(
          () => controller.create(
            type: TransactionType.transfer,
            amountMinor: 100,
            accountId: source,
            destinationAccountId: destination,
            categoryId: categoryId,
          ),
          throwsArgumentError,
        );
      });

      test('rejects an incompatible category type', () async {
        final source = await seedAccount('One');
        final incomeCategory = await seedCategory(
          'Salary',
          type: CategoryType.income,
        );
        expect(
          () => controller.create(
            type: TransactionType.expense,
            amountMinor: 100,
            accountId: source,
            categoryId: incomeCategory,
          ),
          throwsArgumentError,
        );
      });

      test('rejects a missing category', () async {
        final source = await seedAccount('One');
        expect(
          () => controller.create(
            type: TransactionType.expense,
            amountMinor: 100,
            accountId: source,
            categoryId: 'cat-missing',
          ),
          throwsStateError,
        );
      });

      test('rejects an archived category', () async {
        final source = await seedAccount('One');
        final archivedCategory = await seedCategory(
          'Old',
          status: CategoryStatus.archived,
        );
        expect(
          () => controller.create(
            type: TransactionType.expense,
            amountMinor: 100,
            accountId: source,
            categoryId: archivedCategory,
          ),
          throwsStateError,
        );
      });
    });

    test('update changes editable fields and touches updatedAt', () async {
      final source = await seedAccount('One');
      final id = await controller.create(
        type: TransactionType.expense,
        amountMinor: 5000,
        accountId: source,
      );
      final created = await controller.getById(id);

      await _waitForNextSecond();

      await controller.update(
        id: id,
        type: TransactionType.income,
        amountMinor: 90000,
        accountId: source,
        categoryId: await seedCategory('Salary', type: CategoryType.income),
        date: DateTime(2026, 8, 1),
        description: 'Freelance',
      );

      final row = await controller.getById(id);
      expect(row!.type, TransactionType.income);
      expect(row.amountMinor, 90000);
      expect(row.description, 'Freelance');
      expect(row.updatedAt.isAfter(created!.updatedAt), isTrue);
    });

    test('update validates the same rules as create', () async {
      final source = await seedAccount('One');
      final id = await controller.create(
        type: TransactionType.expense,
        amountMinor: 5000,
        accountId: source,
      );

      expect(
        () => controller.update(
          id: id,
          type: TransactionType.transfer,
          amountMinor: 100,
          accountId: source,
          date: DateTime(2026, 8, 1),
        ),
        throwsArgumentError, // transfer without destination
      );
    });

    test('update throws StateError for an unknown id', () async {
      expect(
        () => controller.update(
          id: 'missing',
          type: TransactionType.expense,
          amountMinor: 100,
          accountId: 'acct-any',
          date: DateTime(2026, 8, 1),
        ),
        throwsStateError,
      );
    });

    test('delete removes the transaction', () async {
      final source = await seedAccount('One');
      final id = await controller.create(
        type: TransactionType.expense,
        amountMinor: 5000,
        accountId: source,
      );

      await controller.delete(id);
      expect(await controller.getById(id), isNull);
    });
  });
}

/// Waits until just past the next whole-second boundary.
///
/// Drift stores [DateTime] columns at second precision, so two writes within
/// the same second produce identical timestamps. Tests that assert an ordering
/// between writes must cross a boundary first.
Future<void> _waitForNextSecond() async {
  final now = DateTime.now();
  await Future<void>.delayed(
    Duration(milliseconds: 1000 - now.millisecond + 10),
  );
}
