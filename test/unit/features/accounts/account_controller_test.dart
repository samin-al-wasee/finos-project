import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/application/account_controller.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountController', () {
    late AppDatabase database;
    late AccountDao dao;
    late AccountController controller;

    setUp(() {
      database = AppDatabase.inMemory();
      dao = AccountDao(database);
      controller = AccountController(dao);
    });

    tearDown(() async {
      await database.close();
    });

    test('create generates a stable id and applies the given values', () async {
      final id = await controller.create(
        name: 'Main Bank',
        type: AccountType.bank,
        currency: 'BDT',
        openingBalanceMinor: 5000000,
      );

      final row = await controller.getById(id);
      expect(row, isNotNull);
      expect(row!.id, id);
      expect(row.name, 'Main Bank');
      expect(row.type, AccountType.bank);
      expect(row.currency, 'BDT');
      expect(row.openingBalanceMinor, 5000000);
      expect(row.status, AccountStatus.active);
    });

    test('create defaults to BDT and a zero opening balance', () async {
      final id = await controller.create(
        name: 'Wallet',
        type: AccountType.cash,
      );

      final row = await controller.getById(id);
      expect(row!.currency, 'BDT');
      expect(row.openingBalanceMinor, 0);
    });

    test('generates unique ids across creates', () async {
      final id1 = await controller.create(name: 'A', type: AccountType.cash);
      final id2 = await controller.create(name: 'B', type: AccountType.cash);
      expect(id1, isNot(id2));
    });

    test('getById returns null for an unknown id', () async {
      expect(await controller.getById('missing'), isNull);
    });

    test('update changes editable fields and touches updatedAt', () async {
      final id = await controller.create(
        name: 'Main Bank',
        type: AccountType.bank,
        currency: 'BDT',
        openingBalanceMinor: 100000,
      );

      // Drift stores DateTime with whole-second precision, so wait until the
      // next second boundary to guarantee a strictly later updatedAt.
      await _waitForNextSecond();

      await controller.update(
        id: id,
        name: 'Primary Bank',
        type: AccountType.bank,
        currency: 'USD',
        openingBalanceMinor: 250000,
      );

      final row = await controller.getById(id);
      expect(row!.name, 'Primary Bank');
      expect(row.currency, 'USD');
      expect(row.openingBalanceMinor, 250000);
      expect(row.type, AccountType.bank);
      expect(row.updatedAt.isAfter(row.createdAt), isTrue);
    });

    test('update throws StateError for an unknown id', () async {
      expect(
        () => controller.update(
          id: 'missing',
          name: 'x',
          type: AccountType.cash,
          currency: 'BDT',
          openingBalanceMinor: 0,
        ),
        throwsStateError,
      );
    });

    test('archive and restore transition the lifecycle status', () async {
      final id = await controller.create(name: 'bKash', type: AccountType.mfs);

      await controller.archive(id);
      expect((await controller.getById(id))!.status, AccountStatus.archived);

      await controller.restore(id);
      expect((await controller.getById(id))!.status, AccountStatus.active);
    });

    test('archive throws StateError for an unknown id', () async {
      expect(() => controller.archive('missing'), throwsStateError);
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
