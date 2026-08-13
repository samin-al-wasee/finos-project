import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/application/account_controller.dart';
import 'package:finos_app/features/accounts/application/credit_card_controller.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/data/credit_card_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Credit-card billing details lifecycle: creation atomicity, validation, and
/// the derived statement cycle (docs/DATA_MODEL.md §60, ADR-005).
void main() {
  late AppDatabase database;
  late AccountDao accountDao;
  late CreditCardDao creditCardDao;
  late TransactionDao transactions;
  late CreditCardController controller;

  setUp(() {
    database = AppDatabase.inMemory();
    accountDao = AccountDao(database);
    creditCardDao = CreditCardDao(database);
    transactions = TransactionDao(database);
    controller = CreditCardController(
      database,
      AccountController(accountDao),
      creditCardDao,
      transactions,
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('create', () {
    test('creates the account and its billing details together', () async {
      final accountId = await controller.create(
        name: 'Visa',
        creditLimitMinor: 10000000,
        statementDay: 5,
        paymentDueOffsetDays: 21,
      );

      final account = await accountDao.getById(accountId);
      expect(account, isNotNull);
      expect(account!.name, 'Visa');
      expect(account.type, AccountType.creditCard);

      final details = await creditCardDao.getByAccountId(accountId);
      expect(details, isNotNull);
      expect(details!.creditLimitMinor, 10000000);
      expect(details.statementDay, 5);
      expect(details.paymentDueOffsetDays, 21);
    });

    test('rejects a credit limit that is not positive', () async {
      expect(
        () => controller.create(
          name: 'Visa',
          creditLimitMinor: 0,
          statementDay: 5,
          paymentDueOffsetDays: 21,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a statement day outside 1-31', () async {
      expect(
        () => controller.create(
          name: 'Visa',
          creditLimitMinor: 10000000,
          statementDay: 32,
          paymentDueOffsetDays: 21,
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.create(
          name: 'Visa',
          creditLimitMinor: 10000000,
          statementDay: 0,
          paymentDueOffsetDays: 21,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a negative payment due offset', () async {
      expect(
        () => controller.create(
          name: 'Visa',
          creditLimitMinor: 10000000,
          statementDay: 5,
          paymentDueOffsetDays: -1,
        ),
        throwsArgumentError,
      );
    });

    test('an invalid create leaves no orphaned account row', () async {
      try {
        await controller.create(
          name: 'Visa',
          creditLimitMinor: 0,
          statementDay: 5,
          paymentDueOffsetDays: 21,
        );
      } on ArgumentError {
        // expected
      }

      final accounts = await accountDao.getAll();
      expect(accounts, isEmpty);
    });
  });

  group('update', () {
    test('updates the account and billing details together', () async {
      final accountId = await controller.create(
        name: 'Visa',
        creditLimitMinor: 10000000,
        statementDay: 5,
        paymentDueOffsetDays: 21,
      );

      await controller.update(
        accountId: accountId,
        name: 'Visa Signature',
        currency: 'BDT',
        openingBalanceMinor: 5000,
        creditLimitMinor: 20000000,
        statementDay: 10,
        paymentDueOffsetDays: 25,
      );

      final account = await accountDao.getById(accountId);
      expect(account!.name, 'Visa Signature');
      expect(account.openingBalanceMinor, 5000);

      final details = await creditCardDao.getByAccountId(accountId);
      expect(details!.creditLimitMinor, 20000000);
      expect(details.statementDay, 10);
      expect(details.paymentDueOffsetDays, 25);
    });

    test('throws StateError when the account has no billing details', () async {
      expect(
        () => controller.update(
          accountId: 'missing',
          name: 'Visa',
          currency: 'BDT',
          openingBalanceMinor: 0,
          creditLimitMinor: 10000000,
          statementDay: 5,
          paymentDueOffsetDays: 21,
        ),
        throwsStateError,
      );
    });
  });

  group('cycleFor', () {
    test('returns null for an account with no billing details', () async {
      await accountDao.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-bank',
          name: 'Main Bank',
          type: AccountType.bank,
        ),
      );
      final account = (await accountDao.getById('acct-bank'))!;

      expect(await controller.cycleFor(account), isNull);
    });

    test('derives outstanding, available credit, and the previous statement '
        'balance from transactions around the cutoff', () async {
      final accountId = await controller.create(
        name: 'Visa',
        creditLimitMinor: 10000000,
        statementDay: 5,
        paymentDueOffsetDays: 21,
      );

      // Spent 300,000 before the last statement closed (Aug 5), then another
      // 100,000 in the still-open cycle.
      await transactions.insertOne(
        TransactionRow(
          id: 'tx-before',
          type: TransactionType.expense,
          amountMinor: 300000,
          currency: 'BDT',
          accountId: accountId,
          date: DateTime(2026, 8, 1),
          description: '',
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
        ).toCompanion(true),
      );
      await transactions.insertOne(
        TransactionRow(
          id: 'tx-after',
          type: TransactionType.expense,
          amountMinor: 100000,
          currency: 'BDT',
          accountId: accountId,
          date: DateTime(2026, 8, 8),
          description: '',
          createdAt: DateTime(2026, 8, 8),
          updatedAt: DateTime(2026, 8, 8),
        ).toCompanion(true),
      );

      final account = (await accountDao.getById(accountId))!;
      final cycle = await controller.cycleFor(
        account,
        now: DateTime(2026, 8, 10),
      );

      expect(cycle, isNotNull);
      expect(cycle!.previousStatementDate, DateTime(2026, 8, 5));
      // Only the spend before the cutoff counts toward the locked-in
      // statement balance.
      expect(cycle.previousStatementDebtMinor, 300000);
      // Both transactions count toward the live outstanding balance.
      expect(cycle.outstandingMinor, 400000);
      expect(cycle.availableCreditMinor, 10000000 - 400000);
      expect(cycle.paymentDueDate, DateTime(2026, 8, 26));
      expect(cycle.nextStatementDate, DateTime(2026, 9, 5));
    });
  });
}
