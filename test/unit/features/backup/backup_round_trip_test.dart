import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/backup/application/backup_service.dart';
import 'package:finos_app/features/backup/domain/backup_envelope.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_scope.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/settings/data/settings_dao.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip tests for backup export and restore (FR-08).
///
/// The guarantee under test: exporting and restoring returns the database to
/// exactly the state it was in — same rows, same amounts, same calendar dates.
/// A backup that loses or shifts data is worse than no backup at all.
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late CategoryDao categories;
  late TransactionDao transactions;
  late BudgetDao budgets;
  late BackupService service;

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

  /// Seeds one account, one custom category, income/expense/transfer
  /// transactions, and a budget — one of everything the format carries.
  Future<void> seedEverything() async {
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(5000000),
      ),
    );
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-cash',
        name: 'Cash',
        type: AccountType.cash,
        currency: const Value('USD'),
        status: const Value(AccountStatus.archived),
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-food',
        name: 'Food',
        type: CategoryType.expense,
        icon: const Value('restaurant'),
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-income',
        type: TransactionType.income,
        amountMinor: 10000000,
        accountId: 'acct-bank',
        date: DateTime(2026, 8, 1),
        description: const Value('Salary'),
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-expense',
        type: TransactionType.expense,
        amountMinor: 150000,
        accountId: 'acct-bank',
        categoryId: const Value('test-food'),
        date: DateTime(2026, 8, 3),
        description: const Value('Groceries, with a comma'),
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-transfer',
        type: TransactionType.transfer,
        amountMinor: 500000,
        accountId: 'acct-bank',
        destinationAccountId: const Value('acct-cash'),
        date: DateTime(2026, 8, 5),
      ),
    );
    await budgets.insertOne(
      BudgetsCompanion.insert(
        id: 'budget-food',
        categoryId: const Value('test-food'),
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 8),
      ),
    );
    await budgets.insertOne(
      BudgetsCompanion.insert(
        id: 'budget-custom',
        categoryId: const Value('test-food'),
        amountMinor: 250000,
        period: BudgetPeriod.custom,
        startDate: DateTime(2026, 8, 5),
        endDate: Value(DateTime(2026, 8, 20)),
      ),
    );
  }

  group('export document', () {
    test('carries a version header and every table', () async {
      final json =
          jsonDecode(await service.export(now: DateTime(2026, 8, 10, 12)))
              as Map<String, Object?>;

      expect(json[BackupFormat.versionKey], BackupFormat.version);
      expect(json[BackupFormat.schemaVersionKey], database.schemaVersion);
      expect(json[BackupFormat.exportedAtKey], '2026-08-10T12:00:00.000');
      for (final key in BackupFormat.tableKeys) {
        expect(json[key], isA<List<Object?>>(), reason: 'missing "$key"');
      }
    });

    test('a fresh database exports its seeded built-in categories', () async {
      final json = jsonDecode(await service.export()) as Map<String, Object?>;

      expect(json[BackupFormat.accountsKey], isEmpty);
      expect(json[BackupFormat.transactionsKey], hasLength(0));
      // A fresh install seeds the 12 built-ins, so they are part of a backup.
      expect(json[BackupFormat.categoriesKey], hasLength(12));
    });

    test('does not include user preferences', () async {
      // Preferences describe this device, not the user's finances, so a restore
      // must not repaint the app (docs/DATA_MODEL.md §51).
      await SettingsDao(database).put('theme_preference', 'DARK');

      final json = jsonDecode(await service.export()) as Map<String, Object?>;
      expect(json.containsKey('preferences'), isFalse);
      expect(json.keys, containsAll(BackupFormat.tableKeys));
    });

    test('amounts are written as whole numbers, never decimals', () async {
      await seedEverything();
      final json = jsonDecode(await service.export()) as Map<String, Object?>;

      final tx = (json[BackupFormat.transactionsKey] as List)
          .cast<Map<String, Object?>>()
          .firstWhere((row) => row['id'] == 'tx-expense');
      expect(tx['amount_minor'], isA<int>());
      expect(tx['amount_minor'], 150000);
    });
  });

  group('round trip', () {
    test('restores every row exactly', () async {
      await seedEverything();

      final before = await _snapshot(database);
      final document = await service.export();

      // Wipe by restoring an unrelated backup, then restore the real one, so
      // the assertion cannot pass simply because nothing was touched.
      await service.importBackup(await _emptyBackup(service));
      expect((await _snapshot(database)).accounts, isEmpty);

      await service.importBackup(document);

      final after = await _snapshot(database);
      expect(after.accounts, before.accounts);
      expect(after.categories, before.categories);
      expect(after.transactions, before.transactions);
      expect(after.budgets, before.budgets);
    });

    test('preserves calendar dates without shifting a day', () async {
      // A date stored at local midnight must not drift across a timezone
      // boundary on the way through JSON (docs/DATA_MODEL.md §42).
      await accounts.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-1',
          name: 'Bank',
          type: AccountType.bank,
        ),
      );
      await transactions.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-1',
          type: TransactionType.expense,
          amountMinor: 1000,
          accountId: 'acct-1',
          date: DateTime(2026, 1, 1),
        ),
      );

      final document = await service.export();
      await service.importBackup(document);

      final restored = await transactions.getById('tx-1');
      expect(restored!.date, DateTime(2026, 1, 1));
      expect(restored.date.year, 2026);
      expect(restored.date.month, 1);
      expect(restored.date.day, 1);
    });

    test('preserves transfer links and null categories', () async {
      await seedEverything();
      await service.importBackup(await service.export());

      final transfer = await transactions.getById('tx-transfer');
      expect(transfer!.type, TransactionType.transfer);
      expect(transfer.accountId, 'acct-bank');
      expect(transfer.destinationAccountId, 'acct-cash');
      expect(transfer.categoryId, isNull);
    });

    test('preserves an archived account and its currency', () async {
      await seedEverything();
      await service.importBackup(await service.export());

      final cash = await accounts.getById('acct-cash');
      expect(cash!.status, AccountStatus.archived);
      expect(cash.currency, 'USD');
    });

    test('preserves a custom budget window and a null end date', () async {
      await seedEverything();
      await service.importBackup(await service.export());

      final custom = await budgets.getById('budget-custom');
      expect(custom!.period, BudgetPeriod.custom);
      expect(custom.startDate, DateTime(2026, 8, 5));
      expect(custom.endDate, DateTime(2026, 8, 20));

      final monthly = await budgets.getById('budget-food');
      expect(monthly!.endDate, isNull);
    });

    test('preserves descriptions containing punctuation', () async {
      await seedEverything();
      await service.importBackup(await service.export());

      final expense = await transactions.getById('tx-expense');
      expect(expense!.description, 'Groceries, with a comma');
    });

    test('survives two consecutive round trips unchanged', () async {
      await seedEverything();
      final first = await service.export();
      await service.importBackup(first);
      final second = await service.export();
      await service.importBackup(second);

      // The document itself is stable, so repeated backup/restore cycles cannot
      // slowly mutate the data.
      expect(_withoutTimestamp(second), _withoutTimestamp(first));
    });
  });

  group(
    'flexible scope round trip (docs/adr/007-flexible-budget-scope.md)',
    () {
      test(
        'restores a MULTI_CATEGORY budget with its member categories',
        () async {
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
          await budgets.insertOne(
            BudgetsCompanion.insert(
              id: 'budget-multi',
              categoryId: const Value(null),
              scopeType: const Value(BudgetScopeType.multiCategory),
              amountMinor: 1000000,
              period: BudgetPeriod.monthly,
              startDate: DateTime(2026, 8),
            ),
          );
          await budgets.setCategoriesFor('budget-multi', {
            'test-food',
            'test-transport',
          });

          await service.importBackup(await service.export());

          final restored = await budgets.getById('budget-multi');
          expect(restored!.categoryId, isNull);
          expect(restored.scopeType, BudgetScopeType.multiCategory);
          expect(await budgets.categoriesFor('budget-multi'), {
            'test-food',
            'test-transport',
          });
        },
      );

      test('restores a WHOLE_ACCOUNT budget with a null category', () async {
        await budgets.insertOne(
          BudgetsCompanion.insert(
            id: 'budget-whole',
            categoryId: const Value(null),
            scopeType: const Value(BudgetScopeType.wholeAccount),
            amountMinor: 500000,
            period: BudgetPeriod.yearly,
            startDate: DateTime(2026, 1),
          ),
        );

        await service.importBackup(await service.export());

        final restored = await budgets.getById('budget-whole');
        expect(restored!.categoryId, isNull);
        expect(restored.scopeType, BudgetScopeType.wholeAccount);
      });

      test('restores an UNCATEGORIZED budget with a null category', () async {
        await budgets.insertOne(
          BudgetsCompanion.insert(
            id: 'budget-uncategorized',
            categoryId: const Value(null),
            scopeType: const Value(BudgetScopeType.uncategorized),
            amountMinor: 250000,
            period: BudgetPeriod.monthly,
            startDate: DateTime(2026, 8),
          ),
        );

        await service.importBackup(await service.export());

        final restored = await budgets.getById('budget-uncategorized');
        expect(restored!.categoryId, isNull);
        expect(restored.scopeType, BudgetScopeType.uncategorized);
      });

      test(
        'a SINGLE_CATEGORY-only backup writes no category_ids field, staying '
        'byte-for-byte what it always was',
        () async {
          await seedEverything();
          final json =
              jsonDecode(await service.export()) as Map<String, Object?>;

          final rows = (json[BackupFormat.budgetsKey] as List)
              .cast<Map<String, Object?>>();
          for (final row in rows) {
            expect(row.containsKey('category_ids'), isFalse);
            expect(row['scope_type'], 'SINGLE_CATEGORY');
          }
        },
      );
    },
  );

  group('counts', () {
    test('reports what is currently stored', () async {
      await seedEverything();

      final counts = await service.currentCounts();
      expect(counts.accounts, 2);
      expect(counts.categories, 13); // 12 built-ins plus Food
      expect(counts.transactions, 3);
      expect(counts.budgets, 2);
      expect(counts.total, 20);
      expect(counts.isEmpty, isFalse);
    });

    test('a restore reports what it wrote', () async {
      await seedEverything();
      final document = await service.export();

      final written = await service.importBackup(document);
      expect(written, await service.currentCounts());
    });

    test('an empty database reports empty counts', () async {
      // Built-in categories are seeded, so "empty" still has categories.
      final counts = await service.currentCounts();
      expect(counts.accounts, 0);
      expect(counts.transactions, 0);
      expect(counts.budgets, 0);
      expect(const BackupCounts.empty().isEmpty, isTrue);
    });
  });
}

/// Everything a backup covers, for comparison before and after a round trip.
class _Snapshot {
  const _Snapshot({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.budgets,
  });

  final List<FinancialAccountRow> accounts;
  final List<CategoryRow> categories;
  final List<TransactionRow> transactions;
  final List<BudgetRow> budgets;
}

Future<_Snapshot> _snapshot(AppDatabase database) async {
  return _Snapshot(
    accounts: await (database.select(
      database.financialAccounts,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
    categories: await (database.select(
      database.categories,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
    transactions: await (database.select(
      database.transactions,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
    budgets: await (database.select(
      database.budgets,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
  );
}

/// A valid but empty backup document, used to prove a restore really replaces.
Future<String> _emptyBackup(BackupService service) async {
  return jsonEncode({
    BackupFormat.versionKey: BackupFormat.version,
    BackupFormat.exportedAtKey: DateTime(2026).toIso8601String(),
    for (final key in BackupFormat.tableKeys) key: <Object?>[],
  });
}

/// Drops the export timestamp so two documents can be compared for content.
Map<String, Object?> _withoutTimestamp(String document) {
  final json = jsonDecode(document) as Map<String, Object?>;
  return {...json}..remove(BackupFormat.exportedAtKey);
}
