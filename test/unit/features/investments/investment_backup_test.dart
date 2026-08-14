import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/errors/app_exception.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/backup/application/backup_service.dart';
import 'package:finos_app/features/backup/domain/backup_envelope.dart';
import 'package:finos_app/features/investments/application/investment_controller.dart';
import 'package:finos_app/features/investments/data/investment_dao.dart';
import 'package:finos_app/features/investments/domain/investment_contribution_mode.dart';
import 'package:finos_app/features/investments/domain/investment_instrument_type.dart';
import 'package:finos_app/features/investments/domain/investment_payout_frequency.dart';
import 'package:finos_app/features/recurring/domain/recurrence_frequency.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:flutter_test/flutter_test.dart';

/// Investments in a backup (docs/adr/009-investment-accounting.md).
///
/// A backup that dropped investments would silently lose locked principal
/// while appearing to succeed, so the round trip is checked end to end, the
/// same way `loan_backup_test.dart` checks loans.
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late TransactionDao transactions;
  late InvestmentDao investments;
  late InvestmentController controller;
  late BackupService service;

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
    service = BackupService(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(10000000),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  /// One of each instrument shape: a lump-sum FDR with a payout, and a
  /// periodic-payout Sanchayapatra with one profit payout recorded.
  Future<String> seedInvestments() async {
    final fdr = await controller.create(
      name: '1-year FDR',
      instrumentType: InvestmentInstrumentType.fdr,
      contributionMode: InvestmentContributionMode.lumpSum,
      amountMinor: 2000000,
      sourceAccountId: 'acct-bank',
      payoutAccountId: 'acct-bank',
      startDate: DateTime(2026, 1, 1),
      maturityDate: DateTime(2027, 1, 1),
    );
    await controller.confirmNextPayout(
      fdr,
      amountMinor: 2200000,
      date: DateTime(2027, 1, 1),
    );
    await controller.create(
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
    return fdr;
  }

  group('export', () {
    test('includes an investments section', () async {
      final json = jsonDecode(await service.export()) as Map<String, Object?>;

      expect(json.containsKey(BackupFormat.investmentsKey), isTrue);
      expect(json[BackupFormat.investmentsKey], isA<List<Object?>>());
    });

    test('writes every investment field', () async {
      await seedInvestments();
      final json = jsonDecode(await service.export()) as Map<String, Object?>;

      final entries = (json[BackupFormat.investmentsKey] as List)
          .cast<Map<String, Object?>>();
      expect(entries, hasLength(2));

      final fdr = entries.firstWhere((row) => row['name'] == '1-year FDR');
      expect(fdr['instrument_type'], 'FDR');
      expect(fdr['contribution_mode'], 'LUMP_SUM');
      expect(fdr['amount_minor'], 2000000);
      expect(fdr['currency'], 'BDT');
      expect(fdr['source_account_id'], 'acct-bank');
      expect(fdr['payout_account_id'], 'acct-bank');
      expect(fdr['payout_frequency'], 'AT_MATURITY');
      expect(fdr['next_payout_due'], isNull);

      final sanchayapatra = entries.firstWhere(
        (row) => row['name'] == 'Sanchayapatra',
      );
      expect(sanchayapatra['payout_frequency'], 'QUARTERLY');
      expect(sanchayapatra['next_payout_due'], '2026-04-01T00:00:00.000');
    });

    test('links investment movements to their investment', () async {
      final fdrId = await seedInvestments();
      final json = jsonDecode(await service.export()) as Map<String, Object?>;

      final movements = (json[BackupFormat.transactionsKey] as List)
          .cast<Map<String, Object?>>()
          .where((m) => m['investment_id'] == fdrId)
          .toList();
      expect(movements, hasLength(2)); // contribution plus one payout
      for (final movement in movements) {
        expect(movement['category_id'], isNull);
      }
      expect(movements.map((m) => m['type']).toSet(), {
        'INVESTMENT_CONTRIBUTION',
        'INVESTMENT_PAYOUT',
      });
    });
  });

  group('round trip', () {
    test(
      'restores investments, their movements, and the derived progress',
      () async {
        final fdrId = await seedInvestments();
        final before = await controller.progressFor(
          (await investments.getById(fdrId))!,
        );
        final document = await service.export();

        await service.restore(
          const ParsedBackup(
            accounts: [],
            categories: [],
            transactions: [],
            budgets: [],
            investments: [],
          ),
        );
        expect(await investments.getAll(), isEmpty);

        final counts = await service.importBackup(document);
        expect(counts.investments, 2);

        final restored = await investments.getById(fdrId);
        expect(restored, isNotNull);
        expect(restored!.name, '1-year FDR');
        expect(restored.amountMinor, 2000000);
        expect(restored.maturityDate, DateTime(2027, 1, 1));

        final after = await controller.progressFor(restored);
        expect(after.contributedMinor, before.contributedMinor);
        expect(after.payoutReceivedMinor, before.payoutReceivedMinor);
        expect(after.isSettled, isTrue);
      },
    );

    test('restores the balance effect of investment movements', () async {
      await seedInvestments();
      final document = await service.export();
      final impactBefore = await transactions.balanceImpactFor('acct-bank');

      await service.importBackup(document);

      expect(await transactions.balanceImpactFor('acct-bank'), impactBefore);
    });

    test('counts investments in the totals shown before a restore', () async {
      await seedInvestments();

      final counts = await service.currentCounts();
      expect(counts.investments, 2);
      expect(
        counts.total,
        counts.accounts +
            counts.categories +
            counts.transactions +
            counts.budgets +
            counts.loans +
            counts.investments,
      );
    });
  });

  group('validation', () {
    test('rejects a movement whose investment is missing', () async {
      final contents = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.accountsKey: [
          {
            'id': 'acct-1',
            'name': 'Bank',
            'type': 'BANK',
            'currency': 'BDT',
            'opening_balance_minor': 0,
            'status': 'ACTIVE',
            'created_at': '2026-08-01T00:00:00.000',
            'updated_at': '2026-08-01T00:00:00.000',
          },
        ],
        BackupFormat.transactionsKey: [
          {
            'id': 'tx-orphan',
            'type': 'INVESTMENT_CONTRIBUTION',
            'amount_minor': 1000,
            'currency': 'BDT',
            'account_id': 'acct-1',
            'destination_account_id': null,
            'category_id': null,
            'investment_id': 'inv-ghost',
            'date': '2026-08-03T00:00:00.000',
            'description': '',
            'created_at': '2026-08-03T00:00:00.000',
            'updated_at': '2026-08-03T00:00:00.000',
          },
        ],
      });

      expect(
        () => service.parse(contents),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('inv-ghost'),
          ),
        ),
      );
    });

    test('rejects an investment whose source account is missing', () async {
      final contents = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.investmentsKey: [
          {
            'id': 'inv-1',
            'name': 'FDR',
            'instrument_type': 'FDR',
            'contribution_mode': 'LUMP_SUM',
            'amount_minor': 2000000,
            'currency': 'BDT',
            'source_account_id': 'acct-ghost',
            'payout_account_id': 'acct-ghost',
            'start_date': '2026-01-01T00:00:00.000',
            'maturity_date': '2027-01-01T00:00:00.000',
            'payout_frequency': 'AT_MATURITY',
            'next_contribution_due': null,
            'next_payout_due': null,
            'status': 'ACTIVE',
            'created_at': '2026-01-01T00:00:00.000',
            'updated_at': '2026-01-01T00:00:00.000',
          },
        ],
      });

      expect(
        () => service.parse(contents),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('acct-ghost'),
          ),
        ),
      );
    });

    test('rejects a non-positive amount', () async {
      final contents = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.investmentsKey: [
          {
            'id': 'inv-1',
            'name': 'FDR',
            'instrument_type': 'FDR',
            'contribution_mode': 'LUMP_SUM',
            'amount_minor': 0,
            'currency': 'BDT',
            'source_account_id': 'acct-1',
            'payout_account_id': 'acct-1',
            'start_date': '2026-01-01T00:00:00.000',
            'maturity_date': '2027-01-01T00:00:00.000',
            'payout_frequency': 'AT_MATURITY',
            'next_contribution_due': null,
            'next_payout_due': null,
            'status': 'ACTIVE',
            'created_at': '2026-01-01T00:00:00.000',
            'updated_at': '2026-01-01T00:00:00.000',
          },
        ],
      });

      expect(
        () => service.parse(contents),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('greater than zero'),
          ),
        ),
      );
    });

    test('rejects an unrecognised instrument type', () async {
      final contents = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.investmentsKey: [
          {
            'id': 'inv-1',
            'name': 'FDR',
            'instrument_type': 'BONDS',
            'contribution_mode': 'LUMP_SUM',
            'amount_minor': 2000000,
            'currency': 'BDT',
            'source_account_id': 'acct-1',
            'payout_account_id': 'acct-1',
            'start_date': '2026-01-01T00:00:00.000',
            'maturity_date': '2027-01-01T00:00:00.000',
            'payout_frequency': 'AT_MATURITY',
            'next_contribution_due': null,
            'next_payout_due': null,
            'status': 'ACTIVE',
            'created_at': '2026-01-01T00:00:00.000',
            'updated_at': '2026-01-01T00:00:00.000',
          },
        ],
      });

      expect(
        () => service.parse(contents),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('unrecognised instrument_type'),
          ),
        ),
      );
    });

    test('a backup with no investments section still restores', () async {
      // Backups written before investments existed simply have nothing for
      // them.
      final contents = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.accountsKey: <Object?>[],
        BackupFormat.categoriesKey: <Object?>[],
        BackupFormat.transactionsKey: <Object?>[],
        BackupFormat.budgetsKey: <Object?>[],
      });

      final parsed = service.parse(contents);
      expect(parsed.investments, isEmpty);

      final counts = await service.restore(parsed);
      expect(counts.investments, 0);
    });
  });
}
