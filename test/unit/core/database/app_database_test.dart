import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:finos_app/features/loans/data/loan_dao.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/categories/domain/category_origin.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/recurring/data/recurring_transaction_dao.dart';
import 'package:finos_app/features/recurring/domain/recurrence_frequency.dart';
import 'package:finos_app/features/settings/data/settings_dao.dart';
import 'package:finos_app/features/templates/data/template_dao.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDatabase', () {
    late AppDatabase database;
    late AccountDao dao;

    setUp(() {
      database = AppDatabase.inMemory();
      dao = AccountDao(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('starts at schema version 11', () {
      expect(database.schemaVersion, 11);
    });

    test('seeds the built-in categories on a fresh database', () async {
      final rows = await database.select(database.categories).get();
      expect(rows, hasLength(12));

      // Expense built-ins.
      expect(rows.where((r) => r.type == CategoryType.expense), hasLength(8));
      // Income built-ins.
      expect(rows.where((r) => r.type == CategoryType.income), hasLength(4));

      // All are system categories, active, and have a resolvable icon key.
      for (final row in rows) {
        expect(row.origin, CategoryOrigin.system);
        expect(row.status, CategoryStatus.active);
        expect(row.icon, isNotEmpty);
      }
    });

    test('applies schema defaults and enum storage on insert', () async {
      await dao.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-001',
          name: 'bKash',
          type: AccountType.mfs,
        ),
      );

      final rows = await dao.watchAll().first;
      expect(rows, hasLength(1));

      final row = rows.single;
      expect(row.id, 'acct-001');
      expect(row.name, 'bKash');
      expect(row.type, AccountType.mfs);
      expect(row.status, AccountStatus.active);
      expect(row.currency, 'BDT');
      expect(row.openingBalanceMinor, 0);
      expect(row.createdAt, isNotNull);
      expect(row.updatedAt, isNotNull);
    });

    test('round-trips each account type and status value', () async {
      for (final type in AccountType.values) {
        await dao.insertOne(
          FinancialAccountsCompanion.insert(
            id: 'acct-${type.name}',
            name: type.name,
            type: type,
          ),
        );
      }

      final rows = await dao.watchAll().first;
      expect(rows, hasLength(AccountType.values.length));

      final types = rows.map((r) => r.type).toSet();
      expect(types, AccountType.values.toSet());

      for (final status in AccountStatus.values) {
        await dao.insertOne(
          FinancialAccountsCompanion.insert(
            id: 'acct-${status.name}',
            name: status.name,
            type: AccountType.cash,
            status: Value(status),
          ),
        );
      }

      final withStatus = await dao.watchAll().first;
      final statuses = withStatus.map((r) => r.status).toSet();
      expect(statuses, containsAll(AccountStatus.values));
    });

    test('migrates a v1 database and preserves existing accounts', () async {
      final dir = await Directory.systemTemp.createTemp('finos_migration');
      final file = File('${dir.path}/migration.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      // Hand-roll a schema-v1 database containing only the accounts table,
      // mirroring the pre-FR-03 `FinancialAccounts` schema.
      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 1');
      await legacy.customStatement('''
        CREATE TABLE financial_accounts (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          currency TEXT NOT NULL DEFAULT 'BDT',
          opening_balance_minor INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'ACTIVE'
        )
      ''');
      await legacy.customStatement('''
        INSERT INTO financial_accounts
          (id, name, type, created_at, updated_at)
        VALUES
          ('acct-legacy', 'Legacy Bank', 'BANK', 1700000000, 1700000000)
        ''');
      await legacy.close();

      // Reopen the same file as the current schema (v2). The migration must
      // add the categories table and seed it without touching accounts.
      final migrated = AppDatabase(NativeDatabase(file));
      addTearDown(migrated.close);

      final accounts = await migrated.select(migrated.financialAccounts).get();
      expect(accounts, hasLength(1));
      expect(accounts.single.id, 'acct-legacy');
      expect(accounts.single.name, 'Legacy Bank');
      expect(accounts.single.type, AccountType.bank);
      expect(accounts.single.status, AccountStatus.active);

      // Categories table now exists and is seeded exactly once.
      final categories = await migrated.select(migrated.categories).get();
      expect(categories, hasLength(12));
    });

    test('migrates a v2 database and creates the transactions table', () async {
      final dir = await Directory.systemTemp.createTemp('finos_v2_to_v3');
      final file = File('${dir.path}/migration_v3.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      // Hand-roll a schema-v2 database containing the accounts and categories
      // tables, mirroring the pre-FR-02 schema.
      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 2');
      await legacy.customStatement('''
        CREATE TABLE financial_accounts (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          currency TEXT NOT NULL DEFAULT 'BDT',
          opening_balance_minor INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'ACTIVE'
        )
      ''');
      await legacy.customStatement('''
        CREATE TABLE categories (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          origin TEXT NOT NULL DEFAULT 'USER',
          icon TEXT NOT NULL DEFAULT 'label',
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          created_at INTEGER NOT NULL DEFAULT
            (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
          updated_at INTEGER NOT NULL DEFAULT
            (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
        )
      ''');
      await legacy.customStatement('''
        INSERT INTO financial_accounts
          (id, name, type, created_at, updated_at)
        VALUES
          ('acct-legacy', 'Legacy Bank', 'BANK', 1700000000, 1700000000)
        ''');
      await legacy.close();

      // Reopen the same file as the current schema (v3). The migration must
      // add the transactions table without touching accounts or categories.
      final migrated = AppDatabase(NativeDatabase(file));
      addTearDown(migrated.close);

      // Transactions table now exists and accepts inserts.
      final dao = TransactionDao(migrated);
      await dao.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-001',
          type: TransactionType.expense,
          amountMinor: 5000,
          accountId: 'acct-legacy',
          date: DateTime(2026, 8, 10),
        ),
      );
      final tx = await dao.getById('tx-001');
      expect(tx, isNotNull);
      expect(tx!.type, TransactionType.expense);

      // Existing data is preserved.
      final accounts = await migrated.select(migrated.financialAccounts).get();
      expect(accounts, hasLength(1));
      expect(accounts.single.id, 'acct-legacy');
    });

    test('migrates a v3 database and creates the budgets table', () async {
      final dir = await Directory.systemTemp.createTemp('finos_v3_to_v4');
      final file = File('${dir.path}/migration_v4.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      // Hand-roll a schema-v3 database — accounts, categories, and transactions
      // but no budgets — mirroring the pre-FR-04 schema.
      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 3');
      await legacy.customStatement(_legacyAccountsDdl);
      await legacy.customStatement(_legacyCategoriesDdl);
      await legacy.customStatement(_legacyTransactionsDdl);
      await legacy.customStatement('''
        INSERT INTO financial_accounts
          (id, name, type, created_at, updated_at)
        VALUES
          ('acct-legacy', 'Legacy Bank', 'BANK', 1700000000, 1700000000)
        ''');
      await legacy.customStatement('''
        INSERT INTO transactions
          (id, type, amount_minor, currency, account_id, date,
           description, created_at, updated_at)
        VALUES
          ('tx-legacy', 'EXPENSE', 5000, 'BDT', 'acct-legacy', 1755000000,
           '', 1755000000, 1755000000)
        ''');
      await legacy.close();

      // Reopen as the current schema (v4). The migration must add the budgets
      // table without disturbing existing financial records.
      final migrated = AppDatabase(NativeDatabase(file));
      addTearDown(migrated.close);

      // Budgets table now exists and accepts inserts.
      final dao = BudgetDao(migrated);
      await dao.insertOne(
        BudgetsCompanion.insert(
          id: 'budget-001',
          categoryId: 'cat-food',
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 8),
        ),
      );
      final budget = await dao.getById('budget-001');
      expect(budget, isNotNull);
      expect(budget!.period, BudgetPeriod.monthly);
      expect(budget.status, BudgetStatus.active);
      expect(budget.currency, 'BDT');

      // Existing accounts and transactions are preserved.
      final accounts = await migrated.select(migrated.financialAccounts).get();
      expect(accounts, hasLength(1));
      expect(accounts.single.id, 'acct-legacy');

      final transactions = await TransactionDao(migrated).getAll();
      expect(transactions, hasLength(1));
      expect(transactions.single.id, 'tx-legacy');
    });

    test('recovers a v4 database whose budgets table is missing', () async {
      final dir = await Directory.systemTemp.createTemp('finos_missing_budget');
      final file = File('${dir.path}/missing_budget.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      // A database that claims schema v4 but has no budgets table at all — as if
      // an interrupted migration bumped user_version without creating it.
      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 4');
      await legacy.customStatement(_legacyAccountsDdl);
      await legacy.customStatement(_legacyCategoriesDdl);
      await legacy.customStatement(_legacyTransactionsDdl);
      await legacy.close();

      // Reopen. The beforeOpen safety net must recreate the missing table.
      final reopened = AppDatabase(NativeDatabase(file));
      addTearDown(reopened.close);

      final dao = BudgetDao(reopened);
      await dao.insertOne(
        BudgetsCompanion.insert(
          id: 'budget-safe',
          categoryId: 'cat-transport',
          amountMinor: 500000,
          period: BudgetPeriod.weekly,
          startDate: DateTime(2026, 8, 10),
        ),
      );
      expect(await dao.getById('budget-safe'), isNotNull);
    });

    test('migrates a v4 database and creates the preferences table', () async {
      final dir = await Directory.systemTemp.createTemp('finos_v4_to_v5');
      final file = File('${dir.path}/migration_v5.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      // Hand-roll a schema-v4 database — everything except preferences.
      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 4');
      await legacy.customStatement(_legacyAccountsDdl);
      await legacy.customStatement(_legacyCategoriesDdl);
      await legacy.customStatement(_legacyTransactionsDdl);
      await legacy.customStatement(_legacyBudgetsDdl);
      await legacy.customStatement('''
        INSERT INTO financial_accounts
          (id, name, type, created_at, updated_at)
        VALUES
          ('acct-legacy', 'Legacy Bank', 'BANK', 1700000000, 1700000000)
        ''');
      await legacy.close();

      // Reopen as the current schema (v5).
      final migrated = AppDatabase(NativeDatabase(file));
      addTearDown(migrated.close);

      // The table exists and starts empty — preferences are never seeded,
      // because an absent row means "use the default".
      final dao = SettingsDao(migrated);
      expect(await dao.getAll(), isEmpty);

      await dao.put('theme_preference', 'DARK');
      expect(await dao.getValue('theme_preference'), 'DARK');

      // Existing financial data survives untouched.
      final accounts = await migrated.select(migrated.financialAccounts).get();
      expect(accounts, hasLength(1));
      expect(accounts.single.id, 'acct-legacy');
    });

    test('recovers a v5 database whose preferences table is missing', () async {
      final dir = await Directory.systemTemp.createTemp('finos_missing_prefs');
      final file = File('${dir.path}/missing_prefs.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      // A database claiming schema v5 with no preferences table — an
      // interrupted migration. This one must recover, because the theme is read
      // while the root widget builds.
      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 5');
      await legacy.customStatement(_legacyAccountsDdl);
      await legacy.customStatement(_legacyCategoriesDdl);
      await legacy.customStatement(_legacyTransactionsDdl);
      await legacy.customStatement(_legacyBudgetsDdl);
      await legacy.close();

      final reopened = AppDatabase(NativeDatabase(file));
      addTearDown(reopened.close);

      final dao = SettingsDao(reopened);
      expect(await dao.getAll(), isEmpty);
      await dao.put('default_currency', 'USD');
      expect(await dao.getValue('default_currency'), 'USD');
    });

    test(
      'migrates a v5 database, adding loans and the loan_id column',
      () async {
        final dir = await Directory.systemTemp.createTemp('finos_v5_to_v6');
        final file = File('${dir.path}/migration_v6.db');
        addTearDown(() async {
          await file.delete();
          await dir.delete(recursive: true);
        });

        // Hand-roll a schema-v5 database: everything except loans, and a
        // transactions table with no loan_id column.
        final legacy = _LegacyDatabase(NativeDatabase(file));
        await legacy.customStatement('PRAGMA user_version = 5');
        await legacy.customStatement(_legacyAccountsDdl);
        await legacy.customStatement(_legacyCategoriesDdl);
        await legacy.customStatement(_legacyTransactionsDdl);
        await legacy.customStatement(_legacyBudgetsDdl);
        await legacy.customStatement(_legacyPreferencesDdl);
        await legacy.customStatement('''
        INSERT INTO financial_accounts
          (id, name, type, created_at, updated_at)
        VALUES
          ('acct-legacy', 'Legacy Bank', 'BANK', 1700000000, 1700000000)
        ''');
        await legacy.customStatement('''
        INSERT INTO transactions
          (id, type, amount_minor, currency, account_id, date,
           description, created_at, updated_at)
        VALUES
          ('tx-legacy', 'EXPENSE', 5000, 'BDT', 'acct-legacy', 1755000000,
           '', 1755000000, 1755000000)
        ''');
        await legacy.close();

        final migrated = AppDatabase(NativeDatabase(file));
        addTearDown(migrated.close);

        // The loans table exists and accepts inserts.
        final dao = LoanDao(migrated);
        await dao.insertOne(
          LoansCompanion.insert(
            id: 'loan-001',
            type: LoanDirection.borrowed,
            name: 'Bank Loan',
            principalMinor: 25000000,
            startDate: DateTime(2026, 8, 1),
          ),
        );
        expect(await dao.getById('loan-001'), isNotNull);

        // The existing transaction survived and gained a null loan_id.
        final existing = await TransactionDao(migrated).getById('tx-legacy');
        expect(existing, isNotNull);
        expect(existing!.loanId, isNull);
        expect(existing.amountMinor, 5000);
      },
    );

    test('migrates a v1 database straight through to loans', () async {
      // Regression test: a v1 upgrade creates the transactions table from the
      // *current* schema, which already includes loan_id. Adding the column again
      // in the v6 step threw "duplicate column name" until the step learned to
      // check first.
      final dir = await Directory.systemTemp.createTemp('finos_v1_to_v6');
      final file = File('${dir.path}/migration_v1_v6.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 1');
      await legacy.customStatement(_legacyAccountsDdl);
      await legacy.customStatement('''
        INSERT INTO financial_accounts
          (id, name, type, created_at, updated_at)
        VALUES
          ('acct-legacy', 'Legacy Bank', 'BANK', 1700000000, 1700000000)
        ''');
      await legacy.close();

      final migrated = AppDatabase(NativeDatabase(file));
      addTearDown(migrated.close);

      // Every table from every version now exists, and the account survived.
      expect(await LoanDao(migrated).getAll(), isEmpty);
      expect(await TransactionDao(migrated).getAll(), isEmpty);
      final accounts = await migrated.select(migrated.financialAccounts).get();
      expect(accounts.single.id, 'acct-legacy');
    });

    test(
      'migrates a v6 database and creates the transaction templates table',
      () async {
        final dir = await Directory.systemTemp.createTemp('finos_v6_to_v7');
        final file = File('${dir.path}/migration_v7.db');
        addTearDown(() async {
          await file.delete();
          await dir.delete(recursive: true);
        });

        // Hand-roll a schema-v6 database — everything except templates.
        final legacy = _LegacyDatabase(NativeDatabase(file));
        await legacy.customStatement('PRAGMA user_version = 6');
        await legacy.customStatement(_legacyAccountsDdl);
        await legacy.customStatement(_legacyCategoriesDdl);
        await legacy.customStatement(_legacyTransactionsDdl);
        await legacy.customStatement(_legacyBudgetsDdl);
        await legacy.customStatement(_legacyPreferencesDdl);
        await legacy.customStatement('''
        INSERT INTO financial_accounts
          (id, name, type, created_at, updated_at)
        VALUES
          ('acct-legacy', 'Legacy Bank', 'BANK', 1700000000, 1700000000)
        ''');
        await legacy.close();

        final migrated = AppDatabase(NativeDatabase(file));
        addTearDown(migrated.close);

        // The templates table exists and accepts inserts.
        final dao = TemplateDao(migrated);
        await dao.insertOne(
          TransactionTemplatesCompanion.insert(
            id: 'template-001',
            name: 'Netflix',
            type: TransactionType.expense,
          ),
        );
        expect(await dao.getById('template-001'), isNotNull);

        // Existing financial data survives untouched.
        final accounts = await migrated
            .select(migrated.financialAccounts)
            .get();
        expect(accounts, hasLength(1));
        expect(accounts.single.id, 'acct-legacy');
      },
    );

    test(
      'recovers a v7 database whose transaction templates table is missing',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'finos_missing_templates',
        );
        final file = File('${dir.path}/missing_templates.db');
        addTearDown(() async {
          await file.delete();
          await dir.delete(recursive: true);
        });

        // Build a genuinely correct v7 database, then simulate an
        // interrupted migration by dropping just the templates table while
        // user_version still claims v7.
        final complete = AppDatabase(NativeDatabase(file));
        await complete.customStatement('DROP TABLE transaction_templates');
        await complete.close();

        final reopened = AppDatabase(NativeDatabase(file));
        addTearDown(reopened.close);

        final dao = TemplateDao(reopened);
        await dao.insertOne(
          TransactionTemplatesCompanion.insert(
            id: 'template-safe',
            name: 'Gym membership',
            type: TransactionType.expense,
          ),
        );
        expect(await dao.getById('template-safe'), isNotNull);
      },
    );

    test(
      'migrates a v7 database and creates the recurring transactions table',
      () async {
        final dir = await Directory.systemTemp.createTemp('finos_v7_to_v8');
        final file = File('${dir.path}/migration_v8.db');
        addTearDown(() async {
          await file.delete();
          await dir.delete(recursive: true);
        });

        // Hand-roll a schema-v7 database — everything except recurring
        // transactions.
        final legacy = _LegacyDatabase(NativeDatabase(file));
        await legacy.customStatement('PRAGMA user_version = 7');
        await legacy.customStatement(_legacyAccountsDdl);
        await legacy.customStatement(_legacyCategoriesDdl);
        await legacy.customStatement(_legacyTransactionsDdl);
        await legacy.customStatement(_legacyBudgetsDdl);
        await legacy.customStatement(_legacyPreferencesDdl);
        await legacy.customStatement('''
        INSERT INTO financial_accounts
          (id, name, type, created_at, updated_at)
        VALUES
          ('acct-legacy', 'Legacy Bank', 'BANK', 1700000000, 1700000000)
        ''');
        await legacy.close();

        final migrated = AppDatabase(NativeDatabase(file));
        addTearDown(migrated.close);

        // The recurring transactions table exists and accepts inserts.
        final dao = RecurringTransactionDao(migrated);
        await dao.insertOne(
          RecurringTransactionsCompanion.insert(
            id: 'recurring-001',
            name: 'Netflix',
            type: TransactionType.expense,
            amountMinor: 150000,
            accountId: 'acct-legacy',
            frequency: RecurrenceFrequency.monthly,
            startDate: DateTime(2026, 8, 1),
            nextOccurrence: DateTime(2026, 8, 1),
          ),
        );
        expect(await dao.getById('recurring-001'), isNotNull);

        // Existing financial data survives untouched.
        final accounts = await migrated
            .select(migrated.financialAccounts)
            .get();
        expect(accounts, hasLength(1));
        expect(accounts.single.id, 'acct-legacy');
      },
    );

    test(
      'recovers a v8 database whose recurring transactions table is missing',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'finos_missing_recurring',
        );
        final file = File('${dir.path}/missing_recurring.db');
        addTearDown(() async {
          await file.delete();
          await dir.delete(recursive: true);
        });

        // Build a genuinely correct v8 database, then simulate an
        // interrupted migration by dropping just the recurring transactions
        // table while user_version still claims v8.
        final complete = AppDatabase(NativeDatabase(file));
        await complete.customStatement('DROP TABLE recurring_transactions');
        await complete.close();

        final reopened = AppDatabase(NativeDatabase(file));
        addTearDown(reopened.close);

        await AccountDao(reopened).insertOne(
          FinancialAccountsCompanion.insert(
            id: 'acct-safe',
            name: 'Main Bank',
            type: AccountType.bank,
          ),
        );
        final dao = RecurringTransactionDao(reopened);
        await dao.insertOne(
          RecurringTransactionsCompanion.insert(
            id: 'recurring-safe',
            name: 'Gym membership',
            type: TransactionType.expense,
            amountMinor: 100000,
            accountId: 'acct-safe',
            frequency: RecurrenceFrequency.monthly,
            startDate: DateTime(2026, 8, 1),
            nextOccurrence: DateTime(2026, 8, 1),
          ),
        );
        expect(await dao.getById('recurring-safe'), isNotNull);
      },
    );

    test('recovers a v6 database whose loans table is missing', () async {
      final dir = await Directory.systemTemp.createTemp('finos_missing_loans');
      final file = File('${dir.path}/missing_loans.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      // Claims v6 but has neither the loans table nor the loan_id column — an
      // interrupted migration that got as far as bumping user_version.
      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 6');
      await legacy.customStatement(_legacyAccountsDdl);
      await legacy.customStatement(_legacyCategoriesDdl);
      await legacy.customStatement(_legacyTransactionsDdl);
      await legacy.customStatement(_legacyBudgetsDdl);
      await legacy.customStatement(_legacyPreferencesDdl);
      await legacy.customStatement('''
        INSERT INTO financial_accounts
          (id, name, type, created_at, updated_at)
        VALUES
          ('acct-legacy', 'Legacy Bank', 'BANK', 1700000000, 1700000000)
        ''');
      await legacy.close();

      final reopened = AppDatabase(NativeDatabase(file));
      addTearDown(reopened.close);

      // The safety net recreated both halves, so a loan and its movement work.
      await LoanDao(reopened).insertOne(
        LoansCompanion.insert(
          id: 'loan-safe',
          type: LoanDirection.lent,
          name: 'John',
          principalMinor: 2000000,
          startDate: DateTime(2026, 8, 1),
        ),
      );
      final dao = TransactionDao(reopened);
      await dao.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-safe',
          type: TransactionType.loanPayment,
          amountMinor: 2000000,
          accountId: 'acct-legacy',
          loanId: const Value('loan-safe'),
          date: DateTime(2026, 8, 1),
        ),
      );
      expect((await dao.getById('tx-safe'))!.loanId, 'loan-safe');
    });

    test('recovers a v3 database whose transactions table is missing', () async {
      final dir = await Directory.systemTemp.createTemp('finos_missing_tx');
      final file = File('${dir.path}/missing_tx.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      // A database that claims schema v3 but has no transactions table at all —
      // as if an interrupted build bumped user_version without creating it.
      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 3');
      await legacy.customStatement('''
        CREATE TABLE financial_accounts (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          currency TEXT NOT NULL DEFAULT 'BDT',
          opening_balance_minor INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'ACTIVE'
        )
      ''');
      await legacy.customStatement('''
        CREATE TABLE categories (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          origin TEXT NOT NULL DEFAULT 'USER',
          icon TEXT NOT NULL DEFAULT 'label',
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          created_at INTEGER NOT NULL DEFAULT
            (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
          updated_at INTEGER NOT NULL DEFAULT
            (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
        )
      ''');
      await legacy.close();

      // Reopen. The beforeOpen safety net must recreate the missing table.
      final reopened = AppDatabase(NativeDatabase(file));
      addTearDown(reopened.close);

      // Seed an account so the transaction's foreign key resolves. The
      // hand-rolled table has no timestamp defaults, so provide them.
      final accountDao = AccountDao(reopened);
      await accountDao.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-legacy',
          name: 'Legacy Bank',
          type: AccountType.bank,
          createdAt: Value(DateTime(2026, 8, 10)),
          updatedAt: Value(DateTime(2026, 8, 10)),
        ),
      );

      final dao = TransactionDao(reopened);
      await dao.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-safe',
          type: TransactionType.income,
          amountMinor: 100000,
          accountId: 'acct-legacy',
          date: DateTime(2026, 8, 10),
        ),
      );
      expect(await dao.getById('tx-safe'), isNotNull);

      final accounts = await reopened.select(reopened.financialAccounts).get();
      expect(accounts, hasLength(1));
      expect(accounts.single.id, 'acct-legacy');
    });

    test('recovers a v2 database whose categories table is empty', () async {
      final dir = await Directory.systemTemp.createTemp('finos_empty_cats');
      final file = File('${dir.path}/empty_cats.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      // A database that claims schema v2 (so no migration runs) but whose
      // categories table exists with zero rows — as if a previous migration
      // created the table but the seed failed partway through.
      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 2');
      await legacy.customStatement('''
        CREATE TABLE financial_accounts (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          currency TEXT NOT NULL DEFAULT 'BDT',
          opening_balance_minor INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'ACTIVE'
        )
      ''');
      await legacy.customStatement('''
        CREATE TABLE categories (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          origin TEXT NOT NULL DEFAULT 'USER',
          icon TEXT NOT NULL DEFAULT 'label',
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          created_at INTEGER NOT NULL DEFAULT
            (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
          updated_at INTEGER NOT NULL DEFAULT
            (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
        )
      ''');
      await legacy.close();

      // Reopen. The beforeOpen safety net must notice the empty table and
      // re-seed without touching accounts.
      final reopened = AppDatabase(NativeDatabase(file));
      addTearDown(reopened.close);

      final categories = await reopened.select(reopened.categories).get();
      expect(categories, hasLength(12));

      final accounts = await reopened.select(reopened.financialAccounts).get();
      expect(accounts, isEmpty);
    });

    test('recovers a v2 database whose categories table is missing', () async {
      final dir = await Directory.systemTemp.createTemp('finos_missing_cats');
      final file = File('${dir.path}/missing_cats.db');
      addTearDown(() async {
        await file.delete();
        await dir.delete(recursive: true);
      });

      // A database that claims schema v2 but has no categories table at all —
      // as if an interrupted build bumped user_version without creating it.
      final legacy = _LegacyDatabase(NativeDatabase(file));
      await legacy.customStatement('PRAGMA user_version = 2');
      await legacy.customStatement('''
        CREATE TABLE financial_accounts (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          currency TEXT NOT NULL DEFAULT 'BDT',
          opening_balance_minor INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'ACTIVE'
        )
      ''');
      await legacy.close();

      // Reopen. The safety net must recreate the missing table and seed it.
      final reopened = AppDatabase(NativeDatabase(file));
      addTearDown(reopened.close);

      final categories = await reopened.select(reopened.categories).get();
      expect(categories, hasLength(12));

      final accounts = await reopened.select(reopened.financialAccounts).get();
      expect(accounts, isEmpty);
    });
  });
}

/// Historical DDL for the tables that existed before schema v4.
///
/// Written out by hand rather than derived from the current table definitions so
/// that a legacy database file mirrors the historical schema exactly, even after
/// those definitions change.
const _legacyAccountsDdl = '''
  CREATE TABLE financial_accounts (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'BDT',
    opening_balance_minor INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'ACTIVE'
  )
''';

const _legacyCategoriesDdl = '''
  CREATE TABLE categories (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    origin TEXT NOT NULL DEFAULT 'USER',
    icon TEXT NOT NULL DEFAULT 'label',
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    created_at INTEGER NOT NULL DEFAULT
      (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
    updated_at INTEGER NOT NULL DEFAULT
      (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
  )
''';

const _legacyTransactionsDdl = '''
  CREATE TABLE transactions (
    id TEXT NOT NULL PRIMARY KEY,
    type TEXT NOT NULL,
    amount_minor INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'BDT',
    account_id TEXT NOT NULL REFERENCES financial_accounts (id),
    destination_account_id TEXT REFERENCES financial_accounts (id),
    category_id TEXT REFERENCES categories (id),
    date INTEGER NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL DEFAULT
      (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
    updated_at INTEGER NOT NULL DEFAULT
      (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
  )
''';

const _legacyBudgetsDdl = '''
  CREATE TABLE budgets (
    id TEXT NOT NULL PRIMARY KEY,
    category_id TEXT NOT NULL REFERENCES categories (id),
    amount_minor INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'BDT',
    period TEXT NOT NULL,
    start_date INTEGER NOT NULL,
    end_date INTEGER,
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    created_at INTEGER NOT NULL DEFAULT
      (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
    updated_at INTEGER NOT NULL DEFAULT
      (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
  )
''';

const _legacyPreferencesDdl = '''
  CREATE TABLE preferences (
    key TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL DEFAULT
      (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
  )
''';

/// A minimal schema-v1 database used to hand-roll a pre-FR-03 database.
///
/// No tables are registered — the caller creates the `financial_accounts`
/// table (and stamps `user_version`) with raw SQL so the file mirrors the
/// historical v1 schema exactly, independent of the current table definitions.
class _LegacyDatabase extends GeneratedDatabase {
  _LegacyDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables =>
      const <TableInfo<Table, dynamic>>[];
}
