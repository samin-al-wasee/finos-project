import 'package:drift/drift.dart' hide isNotNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
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

    test('starts at schema version 1', () {
      expect(database.schemaVersion, 1);
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
  });
}
