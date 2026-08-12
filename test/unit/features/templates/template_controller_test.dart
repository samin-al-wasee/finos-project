import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/templates/application/template_controller.dart';
import 'package:finos_app/features/templates/data/template_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [TemplateController] — a template is a preset for manual entry,
/// not a financial record, so validation here only concerns the preset's own
/// shape, never balances or budgets (docs/ROADMAP.md §8.2).
void main() {
  group('TemplateController', () {
    late AppDatabase database;
    late TemplateDao dao;
    late TemplateController controller;

    setUp(() async {
      database = AppDatabase.inMemory();
      dao = TemplateDao(database);
      controller = TemplateController(dao);

      // Real accounts/categories: accountId/categoryId are real foreign
      // keys, so tests that set them need rows to point at.
      await AccountDao(database).insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-1',
          name: 'Main Bank',
          type: AccountType.bank,
        ),
      );
      await AccountDao(database).insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-2',
          name: 'Cash',
          type: AccountType.cash,
        ),
      );
      await CategoryDao(database).insertOne(
        CategoriesCompanion.insert(
          id: 'cat-1',
          name: 'Entertainment',
          type: CategoryType.expense,
        ),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('create applies every given value', () async {
      final id = await controller.create(
        name: 'Netflix',
        type: TransactionType.expense,
        amountMinor: 50000,
        accountId: 'acct-1',
        categoryId: 'cat-1',
        description: 'Monthly subscription',
      );

      final row = await dao.getById(id);
      expect(row, isNotNull);
      expect(row!.name, 'Netflix');
      expect(row.type, TransactionType.expense);
      expect(row.amountMinor, 50000);
      expect(row.accountId, 'acct-1');
      expect(row.categoryId, 'cat-1');
      expect(row.description, 'Monthly subscription');
    });

    test('every field but name is optional', () async {
      final id = await controller.create(
        name: 'Something',
        type: TransactionType.expense,
      );

      final row = await dao.getById(id);
      expect(row!.amountMinor, isNull);
      expect(row.accountId, isNull);
      expect(row.categoryId, isNull);
      expect(row.description, isEmpty);
    });

    test('trims the name', () async {
      final id = await controller.create(
        name: '  Netflix  ',
        type: TransactionType.expense,
      );
      expect((await dao.getById(id))!.name, 'Netflix');
    });

    test('rejects a blank name', () async {
      expect(
        () => controller.create(name: '   ', type: TransactionType.expense),
        throwsArgumentError,
      );
    });

    test('rejects a zero or negative preset amount', () async {
      expect(
        () => controller.create(
          name: 'Test',
          type: TransactionType.expense,
          amountMinor: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.create(
          name: 'Test',
          type: TransactionType.expense,
          amountMinor: -100,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a transfer whose source and destination are the same', () {
      expect(
        () => controller.create(
          name: 'Test',
          type: TransactionType.transfer,
          accountId: 'acct-1',
          destinationAccountId: 'acct-1',
        ),
        throwsArgumentError,
      );
    });

    test('clears the category when the type is a transfer', () async {
      final id = await controller.create(
        name: 'Test',
        type: TransactionType.transfer,
        accountId: 'acct-1',
        destinationAccountId: 'acct-2',
        categoryId: 'cat-1',
      );
      expect((await dao.getById(id))!.categoryId, isNull);
    });

    test('clears the destination account for a non-transfer type', () async {
      final id = await controller.create(
        name: 'Test',
        type: TransactionType.expense,
        accountId: 'acct-1',
        destinationAccountId: 'acct-2',
      );
      expect((await dao.getById(id))!.destinationAccountId, isNull);
    });

    test('update replaces the stored values', () async {
      final id = await controller.create(
        name: 'Netflix',
        type: TransactionType.expense,
        amountMinor: 50000,
      );

      await controller.update(
        id: id,
        name: 'Netflix Premium',
        type: TransactionType.expense,
        amountMinor: 65000,
      );

      final row = await dao.getById(id);
      expect(row!.name, 'Netflix Premium');
      expect(row.amountMinor, 65000);
    });

    test('update throws StateError for an unknown id', () {
      expect(
        () => controller.update(
          id: 'missing',
          name: 'x',
          type: TransactionType.expense,
        ),
        throwsStateError,
      );
    });

    test('update re-validates the same rules as create', () async {
      final id = await controller.create(
        name: 'Test',
        type: TransactionType.expense,
      );
      expect(
        () =>
            controller.update(id: id, name: '', type: TransactionType.expense),
        throwsArgumentError,
      );
    });

    test('delete removes the template', () async {
      final id = await controller.create(
        name: 'Test',
        type: TransactionType.expense,
      );
      await controller.delete(id);
      expect(await dao.getById(id), isNull);
    });
  });
}
