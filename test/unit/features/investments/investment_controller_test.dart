import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/investments/application/investment_controller.dart';
import 'package:finos_app/features/investments/data/investment_dao.dart';
import 'package:finos_app/features/investments/domain/investment_contribution_mode.dart';
import 'package:finos_app/features/investments/domain/investment_instrument_type.dart';
import 'package:finos_app/features/investments/domain/investment_payout_frequency.dart';
import 'package:finos_app/features/investments/domain/investment_status.dart';
import 'package:finos_app/features/recurring/domain/recurrence_frequency.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Investment lifecycle rules: creation, contributions, payouts, maturity,
/// and deletion (docs/adr/009-investment-accounting.md).
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late TransactionDao transactions;
  late InvestmentDao investments;
  late InvestmentController controller;

  setUp(() async {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    transactions = TransactionDao(database);
    investments = InvestmentDao(database);
    controller = InvestmentController(
      database,
      investments,
      transactions,
      accounts,
    );

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(10000000),
      ),
    );
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-closed',
        name: 'Closed Account',
        type: AccountType.bank,
        status: const Value(AccountStatus.archived),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('create — lump sum', () {
    test('stores the investment and records one contribution transaction '
        'atomically', () async {
      final id = await controller.create(
        name: '1-year FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 5000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        startDate: DateTime(2026, 1, 1),
        maturityDate: DateTime(2027, 1, 1),
      );

      final row = await investments.getById(id);
      expect(row, isNotNull);
      expect(row!.name, '1-year FDR');
      expect(row.contributionMode, InvestmentContributionMode.lumpSum);
      expect(row.amountMinor, 5000000);
      expect(row.status, InvestmentStatus.active);
      expect(row.nextContributionDue, isNull);
      expect(row.nextPayoutDue, isNull);

      final movements = await transactions.forInvestment(id);
      expect(movements, hasLength(1));
      expect(movements.single.type, TransactionType.investmentContribution);
      expect(movements.single.amountMinor, 5000000);
      expect(movements.single.accountId, 'acct-bank');
    });

    test('sets nextPayoutDue to the first occurrence after start for a '
        'periodic payout instrument', () async {
      final id = await controller.create(
        name: '5-year Sanchayapatra',
        instrumentType: InvestmentInstrumentType.sanchayapatra,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 10000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        startDate: DateTime(2026, 1, 1),
        maturityDate: DateTime(2031, 1, 1),
        payoutFrequency: const InvestmentPayoutFrequency.periodic(
          RecurrenceFrequency.quarterly,
        ),
      );

      final row = await investments.getById(id);
      // Not the start date itself — profit hasn't accrued yet on day one.
      expect(row!.nextPayoutDue, DateTime(2026, 4, 1));
    });

    test('rejects an empty name', () async {
      expect(
        () => controller.create(
          name: '   ',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 5000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime(2027, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a zero or negative amount', () async {
      expect(
        () => controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 0,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime(2027, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a maturity date on or before the start date', () async {
      expect(
        () => controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 5000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          startDate: DateTime(2026, 1, 1),
          maturityDate: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an archived source account', () async {
      expect(
        () => controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 5000000,
          sourceAccountId: 'acct-closed',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime(2027, 1, 1),
        ),
        throwsStateError,
      );
    });

    test('a rejected creation leaves nothing behind', () async {
      await expectLater(
        () => controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 5000000,
          sourceAccountId: 'acct-ghost',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime(2027, 1, 1),
        ),
        throwsStateError,
      );

      expect(await investments.getAll(), isEmpty);
      expect(await transactions.getAll(), isEmpty);
    });
  });

  group('create — recurring (DPS)', () {
    test('records no transaction, and sets nextContributionDue to the start '
        'date', () async {
      final id = await controller.create(
        name: '3-year DPS',
        instrumentType: InvestmentInstrumentType.dps,
        contributionMode: InvestmentContributionMode.recurring,
        amountMinor: 500000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        startDate: DateTime(2026, 1, 1),
        maturityDate: DateTime(2029, 1, 1),
      );

      final row = await investments.getById(id);
      expect(row!.nextContributionDue, DateTime(2026, 1, 1));
      expect(await transactions.forInvestment(id), isEmpty);
    });
  });

  group('confirmNextContribution / skipNextContribution', () {
    Future<String> createDps({DateTime? startDate, DateTime? maturityDate}) =>
        controller.create(
          name: 'DPS',
          instrumentType: InvestmentInstrumentType.dps,
          contributionMode: InvestmentContributionMode.recurring,
          amountMinor: 500000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          startDate: startDate ?? DateTime(2026, 1, 1),
          maturityDate: maturityDate ?? DateTime(2029, 1, 1),
        );

    test('confirming creates a fixed-amount transaction and advances the '
        'due date by one month', () async {
      final id = await createDps();

      await controller.confirmNextContribution(id);

      final movements = await transactions.forInvestment(id);
      expect(movements, hasLength(1));
      expect(movements.single.type, TransactionType.investmentContribution);
      expect(movements.single.amountMinor, 500000);
      expect(movements.single.date, DateTime(2026, 1, 1));

      final row = await investments.getById(id);
      expect(row!.nextContributionDue, DateTime(2026, 2, 1));
    });

    test(
      'skipping advances the due date without creating a transaction',
      () async {
        final id = await createDps();

        await controller.skipNextContribution(id);

        expect(await transactions.forInvestment(id), isEmpty);
        final row = await investments.getById(id);
        expect(row!.nextContributionDue, DateTime(2026, 2, 1));
      },
    );

    test('does nothing once nextContributionDue is past maturity', () async {
      final id = await createDps(
        startDate: DateTime(2026, 1, 1),
        maturityDate: DateTime(2026, 1, 15),
      );

      // The Jan 1 occurrence is still before the Jan 15 maturity, so this
      // confirms it and advances the due date to Feb 1 — past maturity.
      await controller.confirmNextContribution(id);
      // Feb 1 is past maturity, so this call finds nothing due.
      await controller.confirmNextContribution(id);

      final row = await investments.getById(id);
      expect(row!.nextContributionDue, DateTime(2026, 2, 1));
      expect(await transactions.forInvestment(id), hasLength(1));
    });

    test('throws for an unknown investment', () async {
      expect(
        () => controller.confirmNextContribution('inv-ghost'),
        throwsStateError,
      );
    });
  });

  group('confirmNextPayout / skipNextPayout', () {
    Future<String> createSanchayapatra() => controller.create(
      name: 'Sanchayapatra',
      instrumentType: InvestmentInstrumentType.sanchayapatra,
      contributionMode: InvestmentContributionMode.lumpSum,
      amountMinor: 10000000,
      sourceAccountId: 'acct-bank',
      payoutAccountId: 'acct-bank',
      startDate: DateTime(2026, 1, 1),
      maturityDate: DateTime(2031, 1, 1),
      payoutFrequency: const InvestmentPayoutFrequency.periodic(
        RecurrenceFrequency.quarterly,
      ),
    );

    test('confirming with a user-entered amount creates exactly one '
        'transaction and advances the due date by one quarter', () async {
      final id = await createSanchayapatra();

      final txnId = await controller.confirmNextPayout(
        id,
        amountMinor: 150000,
        date: DateTime(2026, 4, 3),
      );

      final movements = await transactions.forInvestment(id);
      final payouts = movements
          .where((m) => m.type == TransactionType.investmentPayout)
          .toList();
      expect(payouts, hasLength(1));
      expect(payouts.single.id, txnId);
      expect(payouts.single.amountMinor, 150000);
      expect(payouts.single.date, DateTime(2026, 4, 3));

      final row = await investments.getById(id);
      // Advances from the *payout date*, not the previous due date.
      expect(row!.nextPayoutDue, DateTime(2026, 7, 3));
    });

    test('rejects a zero or negative amount', () async {
      final id = await createSanchayapatra();

      expect(
        () => controller.confirmNextPayout(id, amountMinor: 0),
        throwsArgumentError,
      );
    });

    test(
      'does not advance nextPayoutDue for an at-maturity-only instrument',
      () async {
        final id = await controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 5000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          startDate: DateTime(2026, 1, 1),
          maturityDate: DateTime(2027, 1, 1),
        );

        await controller.confirmNextPayout(
          id,
          amountMinor: 5500000,
          date: DateTime(2027, 1, 1),
        );

        final row = await investments.getById(id);
        expect(row!.nextPayoutDue, isNull);
      },
    );

    test(
      'skipping advances the due date without creating a transaction',
      () async {
        final id = await createSanchayapatra();

        await controller.skipNextPayout(id);

        final movements = await transactions.forInvestment(id);
        expect(
          movements.where((m) => m.type == TransactionType.investmentPayout),
          isEmpty,
        );
        final row = await investments.getById(id);
        expect(row!.nextPayoutDue, DateTime(2026, 7, 1));
      },
    );

    test('throws for an unknown investment', () async {
      expect(
        () => controller.confirmNextPayout('inv-ghost', amountMinor: 1000),
        throwsStateError,
      );
    });
  });

  group('update', () {
    test('changes the name only', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 5000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );

      await controller.update(id: id, name: 'Renamed FDR');

      final row = await investments.getById(id);
      expect(row!.name, 'Renamed FDR');
      // Fixed at creation.
      expect(row.amountMinor, 5000000);
    });

    test('rejects an empty name', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 5000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );

      expect(() => controller.update(id: id, name: '  '), throwsArgumentError);
    });

    test('throws for an unknown investment', () async {
      expect(
        () => controller.update(id: 'inv-ghost', name: 'X'),
        throwsStateError,
      );
    });
  });

  group('lifecycle', () {
    test('archive then restore', () async {
      final id = await controller.create(
        name: 'FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 5000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2027, 1, 1),
      );

      await controller.archive(id);
      expect(
        (await investments.getById(id))!.status,
        InvestmentStatus.archived,
      );

      await controller.restore(id);
      expect((await investments.getById(id))!.status, InvestmentStatus.active);
    });

    test(
      'deleting an investment removes its contribution transaction too',
      () async {
        final id = await controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 5000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime(2027, 1, 1),
        );
        expect(await transactions.getAll(), hasLength(1));

        await controller.delete(id);

        expect(await investments.getById(id), isNull);
        expect(await transactions.getAll(), isEmpty);
        expect(await transactions.balanceImpactFor('acct-bank'), 0);
      },
    );

    test(
      'refuses to delete a lump-sum investment once a payout is recorded',
      () async {
        final id = await controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 5000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime(2027, 1, 1),
        );
        await controller.confirmNextPayout(id, amountMinor: 100000);

        await expectLater(
          () => controller.delete(id),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message.toString(),
              'message',
              contains('Archive it instead'),
            ),
          ),
        );

        expect(await investments.getById(id), isNotNull);
      },
    );

    test('refuses to delete a recurring investment once a contribution is '
        'confirmed', () async {
      final id = await controller.create(
        name: 'DPS',
        instrumentType: InvestmentInstrumentType.dps,
        contributionMode: InvestmentContributionMode.recurring,
        amountMinor: 500000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2029, 1, 1),
      );
      await controller.confirmNextContribution(id);

      await expectLater(
        () => controller.delete(id),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('Archive it instead'),
          ),
        ),
      );

      expect(await investments.getById(id), isNotNull);
    });

    test('deletes a recurring investment with no movements at all', () async {
      final id = await controller.create(
        name: 'DPS',
        instrumentType: InvestmentInstrumentType.dps,
        contributionMode: InvestmentContributionMode.recurring,
        amountMinor: 500000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime(2029, 1, 1),
      );

      await controller.delete(id);

      expect(await investments.getById(id), isNull);
    });

    test('delete throws for an unknown investment', () async {
      expect(() => controller.delete('inv-ghost'), throwsStateError);
    });
  });

  group('progressFor', () {
    test(
      'sums contributions and payouts, and tracks the latest payout date',
      () async {
        final id = await controller.create(
          name: 'Sanchayapatra',
          instrumentType: InvestmentInstrumentType.sanchayapatra,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 10000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          startDate: DateTime(2026, 1, 1),
          maturityDate: DateTime(2031, 1, 1),
          payoutFrequency: const InvestmentPayoutFrequency.periodic(
            RecurrenceFrequency.quarterly,
          ),
        );
        await controller.confirmNextPayout(
          id,
          amountMinor: 150000,
          date: DateTime(2026, 4, 1),
        );
        await controller.confirmNextPayout(
          id,
          amountMinor: 150000,
          date: DateTime(2026, 7, 1),
        );

        final row = (await investments.getById(id))!;
        final progress = await controller.progressFor(row);

        expect(progress.contributedMinor, 10000000);
        expect(progress.payoutReceivedMinor, 300000);
        expect(progress.latestPayoutDate, DateTime(2026, 7, 1));
        expect(progress.isMatured(now: DateTime(2026, 8, 1)), isFalse);
        expect(progress.isMaturityPayoutDue(now: DateTime(2031, 1, 2)), isTrue);
      },
    );

    test(
      'a payout dated on the maturity date satisfies the maturity payout',
      () async {
        final id = await controller.create(
          name: 'FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 5000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          startDate: DateTime(2026, 1, 1),
          maturityDate: DateTime(2027, 1, 1),
        );
        await controller.confirmNextPayout(
          id,
          amountMinor: 5500000,
          date: DateTime(2027, 1, 1),
        );

        final row = (await investments.getById(id))!;
        final progress = await controller.progressFor(row);

        expect(progress.isMatured(now: DateTime(2027, 1, 1)), isTrue);
        expect(
          progress.isMaturityPayoutDue(now: DateTime(2027, 1, 1)),
          isFalse,
        );
      },
    );
  });
}
