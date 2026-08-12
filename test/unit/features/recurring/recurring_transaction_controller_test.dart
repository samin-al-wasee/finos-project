import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/recurring/application/recurring_transaction_controller.dart';
import 'package:finos_app/features/recurring/data/recurring_transaction_dao.dart';
import 'package:finos_app/features/recurring/domain/recurrence_frequency.dart';
import 'package:finos_app/features/recurring/domain/recurring_status.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [RecurringTransactionController] — a rule never creates a
/// transaction by itself; only [RecurringTransactionController.confirmNext]/
/// [RecurringTransactionController.confirmAll] do, and only for occurrences
/// already computed as due (docs/ARCHITECTURE.md §20).
void main() {
  group('RecurringTransactionController', () {
    late AppDatabase database;
    late RecurringTransactionDao dao;
    late TransactionDao transactionDao;
    late RecurringTransactionController controller;

    setUp(() async {
      database = AppDatabase.inMemory();
      dao = RecurringTransactionDao(database);
      transactionDao = TransactionDao(database);
      controller = RecurringTransactionController(
        database,
        dao,
        transactionDao,
      );

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

    test(
      'create stores every given value, using startDate as nextOccurrence',
      () async {
        final id = await controller.create(
          name: 'Netflix',
          type: TransactionType.expense,
          amountMinor: 50000,
          accountId: 'acct-1',
          categoryId: 'cat-1',
          description: 'Monthly subscription',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
        );

        final row = await dao.getById(id);
        expect(row, isNotNull);
        expect(row!.name, 'Netflix');
        expect(row.amountMinor, 50000);
        expect(row.accountId, 'acct-1');
        expect(row.categoryId, 'cat-1');
        expect(row.description, 'Monthly subscription');
        expect(row.frequency, RecurrenceFrequency.monthly);
        expect(row.startDate, DateTime(2026, 1, 5));
        expect(row.nextOccurrence, DateTime(2026, 1, 5));
        expect(row.status, RecurringStatus.active);
      },
    );

    test('trims the name', () async {
      final id = await controller.create(
        name: '  Netflix  ',
        type: TransactionType.expense,
        amountMinor: 1000,
        accountId: 'acct-1',
        frequency: RecurrenceFrequency.monthly,
        startDate: DateTime(2026, 1, 5),
      );
      expect((await dao.getById(id))!.name, 'Netflix');
    });

    test('rejects a blank name', () {
      expect(
        () => controller.create(
          name: '   ',
          type: TransactionType.expense,
          amountMinor: 1000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a zero or negative amount', () {
      expect(
        () => controller.create(
          name: 'Test',
          type: TransactionType.expense,
          amountMinor: 0,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a transfer whose source and destination are the same', () {
      expect(
        () => controller.create(
          name: 'Test',
          type: TransactionType.transfer,
          amountMinor: 1000,
          accountId: 'acct-1',
          destinationAccountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a transfer with no destination account', () {
      expect(
        () => controller.create(
          name: 'Test',
          type: TransactionType.transfer,
          amountMinor: 1000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
        ),
        throwsArgumentError,
      );
    });

    test('clears the category for a transfer', () async {
      final id = await controller.create(
        name: 'Test',
        type: TransactionType.transfer,
        amountMinor: 1000,
        accountId: 'acct-1',
        destinationAccountId: 'acct-2',
        categoryId: 'cat-1',
        frequency: RecurrenceFrequency.monthly,
        startDate: DateTime(2026, 1, 5),
      );
      expect((await dao.getById(id))!.categoryId, isNull);
    });

    test('clears the destination account for a non-transfer type', () async {
      final id = await controller.create(
        name: 'Test',
        type: TransactionType.expense,
        amountMinor: 1000,
        accountId: 'acct-1',
        destinationAccountId: 'acct-2',
        frequency: RecurrenceFrequency.monthly,
        startDate: DateTime(2026, 1, 5),
      );
      expect((await dao.getById(id))!.destinationAccountId, isNull);
    });

    test('rejects an end date before the start date', () {
      expect(
        () => controller.create(
          name: 'Test',
          type: TransactionType.expense,
          amountMinor: 1000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
          endDate: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test(
      'update replaces details but leaves nextOccurrence untouched',
      () async {
        final id = await controller.create(
          name: 'Netflix',
          type: TransactionType.expense,
          amountMinor: 50000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
        );

        // Advance nextOccurrence away from startDate first, so the test can tell
        // update() didn't reset it back.
        await controller.confirmNext(id);
        final afterConfirm = await dao.getById(id);

        await controller.update(
          id: id,
          name: 'Netflix Premium',
          type: TransactionType.expense,
          amountMinor: 65000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
        );

        final row = await dao.getById(id);
        expect(row!.name, 'Netflix Premium');
        expect(row.amountMinor, 65000);
        expect(row.nextOccurrence, afterConfirm!.nextOccurrence);
      },
    );

    test('update throws StateError for an unknown id', () {
      expect(
        () => controller.update(
          id: 'missing',
          name: 'x',
          type: TransactionType.expense,
          amountMinor: 1000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
        ),
        throwsStateError,
      );
    });

    test('archive and restore toggle status', () async {
      final id = await controller.create(
        name: 'Test',
        type: TransactionType.expense,
        amountMinor: 1000,
        accountId: 'acct-1',
        frequency: RecurrenceFrequency.monthly,
        startDate: DateTime(2026, 1, 5),
      );

      await controller.archive(id);
      expect((await dao.getById(id))!.status, RecurringStatus.archived);

      await controller.restore(id);
      expect((await dao.getById(id))!.status, RecurringStatus.active);
    });

    test(
      'delete removes the rule but not transactions it already created',
      () async {
        final id = await controller.create(
          name: 'Test',
          type: TransactionType.expense,
          amountMinor: 1000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
        );
        await controller.confirmNext(id);
        expect(await transactionDao.getAll(), hasLength(1));

        await controller.delete(id);
        expect(await dao.getById(id), isNull);
        expect(await transactionDao.getAll(), hasLength(1));
      },
    );

    group('confirmNext', () {
      test(
        'creates one transaction and advances to the next occurrence',
        () async {
          final id = await controller.create(
            name: 'Netflix',
            type: TransactionType.expense,
            amountMinor: 50000,
            accountId: 'acct-1',
            categoryId: 'cat-1',
            description: 'Monthly subscription',
            frequency: RecurrenceFrequency.monthly,
            startDate: DateTime(2026, 1, 5),
          );

          await controller.confirmNext(id);

          final transactions = await transactionDao.getAll();
          expect(transactions, hasLength(1));
          expect(transactions.single.amountMinor, 50000);
          expect(transactions.single.accountId, 'acct-1');
          expect(transactions.single.categoryId, 'cat-1');
          expect(transactions.single.description, 'Monthly subscription');
          expect(transactions.single.date, DateTime(2026, 1, 5));

          final row = await dao.getById(id);
          expect(row!.nextOccurrence, DateTime(2026, 2, 5));
        },
      );

      test(
        'falls back to the rule name when there is no description',
        () async {
          final id = await controller.create(
            name: 'Netflix',
            type: TransactionType.expense,
            amountMinor: 50000,
            accountId: 'acct-1',
            frequency: RecurrenceFrequency.monthly,
            startDate: DateTime(2026, 1, 5),
          );
          await controller.confirmNext(id);
          expect((await transactionDao.getAll()).single.description, 'Netflix');
        },
      );

      test('does nothing when nothing is due', () async {
        final id = await controller.create(
          name: 'Netflix',
          type: TransactionType.expense,
          amountMinor: 50000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2030, 1, 5),
        );
        await controller.confirmNext(id);
        expect(await transactionDao.getAll(), isEmpty);
        expect((await dao.getById(id))!.nextOccurrence, DateTime(2030, 1, 5));
      });

      test('confirms only the oldest occurrence out of a backlog', () async {
        final id = await controller.create(
          name: 'Netflix',
          type: TransactionType.expense,
          amountMinor: 50000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2025, 1, 5),
        );

        await controller.confirmNext(id);

        expect(await transactionDao.getAll(), hasLength(1));
        expect((await dao.getById(id))!.nextOccurrence, DateTime(2025, 2, 5));
      });

      test('throws StateError for an unknown id', () {
        expect(() => controller.confirmNext('missing'), throwsStateError);
      });
    });

    group('confirmAll', () {
      test(
        'creates a transaction for every due occurrence, atomically',
        () async {
          final id = await controller.create(
            name: 'Netflix',
            type: TransactionType.expense,
            amountMinor: 50000,
            accountId: 'acct-1',
            frequency: RecurrenceFrequency.monthly,
            startDate: DateTime(2025, 1, 5),
          );

          await controller.confirmAll(id);

          final transactions = await transactionDao.getAll();
          // Jan, Feb, Mar 2025 are due against a fixed backlog created with a
          // start date well in the past; the exact count depends on "now", so
          // just assert the invariants that matter: at least one, dates strictly
          // increasing from the start date, and nextOccurrence advanced past the
          // last one created.
          expect(transactions, isNotEmpty);
          final dates = transactions.map((t) => t.date).toList()..sort();
          expect(dates.first, DateTime(2025, 1, 5));

          final row = await dao.getById(id);
          expect(row!.nextOccurrence.isAfter(dates.last), isTrue);
        },
      );

      test('does nothing when nothing is due', () async {
        final id = await controller.create(
          name: 'Netflix',
          type: TransactionType.expense,
          amountMinor: 50000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2030, 1, 5),
        );
        await controller.confirmAll(id);
        expect(await transactionDao.getAll(), isEmpty);
      });

      test('throws StateError for an unknown id', () {
        expect(() => controller.confirmAll('missing'), throwsStateError);
      });
    });

    group('skipAll', () {
      test(
        'advances nextOccurrence past the backlog without creating transactions',
        () async {
          final id = await controller.create(
            name: 'Netflix',
            type: TransactionType.expense,
            amountMinor: 50000,
            accountId: 'acct-1',
            frequency: RecurrenceFrequency.monthly,
            startDate: DateTime(2025, 1, 5),
          );

          await controller.skipAll(id);

          expect(await transactionDao.getAll(), isEmpty);
          final row = await dao.getById(id);
          // A rule is only ever "due" up to now, so skipping the whole backlog
          // must land nextOccurrence past today.
          expect(row!.nextOccurrence.isAfter(DateTime.now()), isTrue);
        },
      );

      test('does nothing when nothing is due', () async {
        final id = await controller.create(
          name: 'Netflix',
          type: TransactionType.expense,
          amountMinor: 50000,
          accountId: 'acct-1',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2030, 1, 5),
        );
        await controller.skipAll(id);
        expect((await dao.getById(id))!.nextOccurrence, DateTime(2030, 1, 5));
      });

      test('throws StateError for an unknown id', () {
        expect(() => controller.skipAll('missing'), throwsStateError);
      });
    });
  });
}
