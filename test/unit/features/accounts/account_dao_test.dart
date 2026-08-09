import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountDao', () {
    late AppDatabase database;
    late AccountDao dao;

    setUp(() {
      database = AppDatabase.inMemory();
      dao = AccountDao(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> seed(
      String name, {
      AccountStatus status = AccountStatus.active,
    }) async {
      final id = 'acct-$name';
      await dao.insertOne(
        FinancialAccountsCompanion.insert(
          id: id,
          name: name,
          type: AccountType.bank,
          status: Value(status),
        ),
      );
      return id;
    }

    test('getById returns the matching row', () async {
      await seed('One');
      await seed('Two');

      final row = await dao.getById('acct-Two');
      expect(row, isNotNull);
      expect(row!.name, 'Two');
    });

    test('getById returns null when no row matches', () async {
      expect(await dao.getById('missing'), isNull);
    });

    test('updateOne replaces the row contents', () async {
      final id = await seed('Before');

      final row = await dao.getById(id);
      await dao.updateOne(
        row!.copyWith(name: 'After', openingBalanceMinor: 777777),
      );

      final updated = await dao.getById(id);
      expect(updated!.name, 'After');
      expect(updated.openingBalanceMinor, 777777);
    });

    test('updateStatus transitions the lifecycle status', () async {
      final id = await seed('Status');

      await dao.updateStatus(id, AccountStatus.archived);
      expect((await dao.getById(id))!.status, AccountStatus.archived);

      await dao.updateStatus(id, AccountStatus.active);
      expect((await dao.getById(id))!.status, AccountStatus.active);
    });

    test('updateStatus throws StateError for an unknown id', () async {
      expect(
        () => dao.updateStatus('missing', AccountStatus.archived),
        throwsStateError,
      );
    });
  });
}
