import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/categories/domain/category_origin.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
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

    test('starts at schema version 2', () {
      expect(database.schemaVersion, 2);
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
