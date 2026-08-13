import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/errors/app_exception.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/backup/application/backup_service.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_scope.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_origin.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/settings/data/settings_dao.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Restore semantics: replacement and atomicity (AGENTS.md §14).
///
/// The promise a user is given at the confirmation dialog is that a restore
/// either lands completely or changes nothing. These tests hold it to that.
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late CategoryDao categories;
  late TransactionDao transactions;
  late BudgetDao budgets;
  late BackupService service;

  final timestamp = DateTime(2026, 8, 10);

  setUp(() {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    categories = CategoryDao(database);
    transactions = TransactionDao(database);
    budgets = BudgetDao(database);
    service = BackupService(database);
  });

  tearDown(() async {
    await database.close();
  });

  /// Seeds data that a restore is expected to replace.
  Future<void> seedExisting() async {
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-old',
        name: 'Old Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(100000),
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'cat-old',
        name: 'Old Category',
        type: CategoryType.expense,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-old',
        type: TransactionType.expense,
        amountMinor: 50000,
        accountId: 'acct-old',
        categoryId: const Value('cat-old'),
        date: DateTime(2026, 7, 1),
      ),
    );
    await budgets.insertOne(
      BudgetsCompanion.insert(
        id: 'budget-old',
        categoryId: const Value('cat-old'),
        amountMinor: 500000,
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 7),
      ),
    );
  }

  FinancialAccountRow accountRow(String id) => FinancialAccountRow(
    id: id,
    name: 'New Bank',
    type: AccountType.bank,
    currency: 'BDT',
    openingBalanceMinor: 0,
    status: AccountStatus.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  CategoryRow categoryRow(String id) => CategoryRow(
    id: id,
    name: 'New Category',
    type: CategoryType.expense,
    origin: CategoryOrigin.user,
    icon: 'label',
    status: CategoryStatus.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  TransactionRow transactionRow(
    String id, {
    required String accountId,
    String? categoryId,
  }) => TransactionRow(
    id: id,
    type: TransactionType.expense,
    amountMinor: 1000,
    currency: 'BDT',
    accountId: accountId,
    destinationAccountId: null,
    categoryId: categoryId,
    date: timestamp,
    description: '',
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  BudgetRow budgetRow(String id, {required String categoryId}) => BudgetRow(
    id: id,
    categoryId: categoryId,
    scopeType: BudgetScopeType.singleCategory,
    amountMinor: 200000,
    currency: 'BDT',
    period: BudgetPeriod.monthly,
    startDate: timestamp,
    endDate: null,
    status: BudgetStatus.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  group('replacement', () {
    test('removes records the backup does not contain', () async {
      await seedExisting();

      await service.restore(
        ParsedBackup(
          accounts: [accountRow('acct-new')],
          categories: [categoryRow('cat-new')],
          transactions: const [],
          budgets: const [],
        ),
      );

      expect(await accounts.getById('acct-old'), isNull);
      expect(await categories.getById('cat-old'), isNull);
      expect(await transactions.getById('tx-old'), isNull);
      expect(await budgets.getById('budget-old'), isNull);
      expect(await accounts.getById('acct-new'), isNotNull);
    });

    test('replaces the seeded built-in categories too', () async {
      // Built-ins are ordinary rows, so a backup is the single source of truth
      // for what categories exist after a restore.
      expect(await categories.getAll(), hasLength(12));

      await service.restore(
        ParsedBackup(
          accounts: const [],
          categories: [categoryRow('cat-only')],
          transactions: const [],
          budgets: const [],
        ),
      );

      final remaining = await categories.getAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.id, 'cat-only');
    });

    test('an empty backup clears everything', () async {
      await seedExisting();

      final counts = await service.restore(
        const ParsedBackup(
          accounts: [],
          categories: [],
          transactions: [],
          budgets: [],
        ),
      );

      expect(counts.isEmpty, isTrue);
      expect((await service.currentCounts()).total, 0);
    });

    test('leaves user preferences untouched', () async {
      // Preferences are not part of a backup, so a restore must not disturb the
      // user's theme or currency (docs/DATA_MODEL.md §51).
      final settings = SettingsDao(database);
      await settings.put('theme_preference', 'DARK');
      await settings.put('default_currency', 'USD');
      await seedExisting();

      await service.restore(
        const ParsedBackup(
          accounts: [],
          categories: [],
          transactions: [],
          budgets: [],
        ),
      );

      expect(await settings.getValue('theme_preference'), 'DARK');
      expect(await settings.getValue('default_currency'), 'USD');
    });

    test('reports the counts it wrote', () async {
      final counts = await service.restore(
        ParsedBackup(
          accounts: [accountRow('acct-1')],
          categories: [categoryRow('cat-1')],
          transactions: [
            transactionRow('tx-1', accountId: 'acct-1', categoryId: 'cat-1'),
          ],
          budgets: [budgetRow('budget-1', categoryId: 'cat-1')],
        ),
      );

      expect(counts.accounts, 1);
      expect(counts.categories, 1);
      expect(counts.transactions, 1);
      expect(counts.budgets, 1);
      expect(counts.total, 4);
    });
  });

  group('atomicity', () {
    test('a failure part-way through changes nothing', () async {
      await seedExisting();
      final before = await service.currentCounts();

      // A transaction referencing an account the backup does not contain. Normal
      // imports can't reach this state because parse() rejects it first, so this
      // goes straight to restore() to exercise the rollback path itself: the
      // accounts and categories inserts succeed, then the foreign key fails.
      await expectLater(
        () => service.restore(
          ParsedBackup(
            accounts: [accountRow('acct-new')],
            categories: [categoryRow('cat-new')],
            transactions: [transactionRow('tx-bad', accountId: 'acct-ghost')],
            budgets: const [],
          ),
        ),
        throwsA(isA<PersistenceException>()),
      );

      // Every original row is still present, and nothing from the failed backup
      // leaked in.
      expect(await service.currentCounts(), before);
      expect(await accounts.getById('acct-old'), isNotNull);
      expect(await categories.getById('cat-old'), isNotNull);
      expect(await transactions.getById('tx-old'), isNotNull);
      expect(await budgets.getById('budget-old'), isNotNull);
      expect(await accounts.getById('acct-new'), isNull);
      expect(await categories.getById('cat-new'), isNull);
    });

    test('a failing restore reports a readable message', () async {
      await seedExisting();

      await expectLater(
        () => service.restore(
          ParsedBackup(
            accounts: const [],
            categories: const [],
            transactions: [transactionRow('tx-bad', accountId: 'acct-ghost')],
            budgets: const [],
          ),
        ),
        throwsA(
          isA<PersistenceException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('nothing was changed'),
              contains('existing data is untouched'),
            ),
          ),
        ),
      );
    });

    test('a broken budget reference also rolls back', () async {
      await seedExisting();
      final before = await service.currentCounts();

      await expectLater(
        () => service.restore(
          ParsedBackup(
            accounts: [accountRow('acct-new')],
            categories: const [],
            transactions: const [],
            budgets: [budgetRow('budget-bad', categoryId: 'cat-ghost')],
          ),
        ),
        throwsA(isA<PersistenceException>()),
      );

      expect(await service.currentCounts(), before);
    });

    test('the database still works after a failed restore', () async {
      await seedExisting();

      await expectLater(
        () => service.restore(
          ParsedBackup(
            accounts: const [],
            categories: const [],
            transactions: [transactionRow('tx-bad', accountId: 'acct-ghost')],
            budgets: const [],
          ),
        ),
        throwsA(isA<PersistenceException>()),
      );

      // A rolled-back transaction must leave the connection usable, so the user
      // can retry with a good file.
      await service.restore(
        ParsedBackup(
          accounts: [accountRow('acct-good')],
          categories: const [],
          transactions: const [],
          budgets: const [],
        ),
      );
      expect(await accounts.getById('acct-good'), isNotNull);
    });
  });
}
