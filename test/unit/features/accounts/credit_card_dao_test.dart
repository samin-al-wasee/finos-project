import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/data/credit_card_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreditCardDao', () {
    late AppDatabase database;
    late AccountDao accounts;
    late CreditCardDao dao;

    setUp(() {
      database = AppDatabase.inMemory();
      accounts = AccountDao(database);
      dao = CreditCardDao(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> seedAccount(String name) async {
      final id = 'acct-$name';
      await accounts.insertOne(
        FinancialAccountsCompanion.insert(
          id: id,
          name: name,
          type: AccountType.creditCard,
        ),
      );
      return id;
    }

    test('getByAccountId returns null when no details exist', () async {
      final accountId = await seedAccount('One');
      expect(await dao.getByAccountId(accountId), isNull);
    });

    test('insertOne then getByAccountId returns the row', () async {
      final accountId = await seedAccount('One');
      await dao.insertOne(
        CreditCardDetailsCompanion.insert(
          id: 'card-1',
          accountId: accountId,
          creditLimitMinor: 10000000,
          statementDay: 5,
          paymentDueOffsetDays: 21,
        ),
      );

      final row = await dao.getByAccountId(accountId);
      expect(row, isNotNull);
      expect(row!.creditLimitMinor, 10000000);
      expect(row.statementDay, 5);
      expect(row.paymentDueOffsetDays, 21);
    });

    test('updateOne replaces the row contents', () async {
      final accountId = await seedAccount('One');
      await dao.insertOne(
        CreditCardDetailsCompanion.insert(
          id: 'card-1',
          accountId: accountId,
          creditLimitMinor: 10000000,
          statementDay: 5,
          paymentDueOffsetDays: 21,
        ),
      );

      final row = await dao.getByAccountId(accountId);
      await dao.updateOne(
        row!.copyWith(creditLimitMinor: 20000000, statementDay: 10),
      );

      final updated = await dao.getByAccountId(accountId);
      expect(updated!.creditLimitMinor, 20000000);
      expect(updated.statementDay, 10);
      // Untouched fields survive the update.
      expect(updated.paymentDueOffsetDays, 21);
    });

    test('watchByAccountId emits null, then the row once inserted', () async {
      final accountId = await seedAccount('One');

      final emissions = <CreditCardDetailsRow?>[];
      final subscription = dao
          .watchByAccountId(accountId)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      // Let the first (null) emission land before inserting.
      await pumpEventQueue();
      expect(emissions, [isNull]);

      await dao.insertOne(
        CreditCardDetailsCompanion.insert(
          id: 'card-1',
          accountId: accountId,
          creditLimitMinor: 10000000,
          statementDay: 5,
          paymentDueOffsetDays: 21,
        ),
      );
      await pumpEventQueue();

      expect(emissions, hasLength(2));
      expect(emissions.last!.creditLimitMinor, 10000000);
    });
  });
}
