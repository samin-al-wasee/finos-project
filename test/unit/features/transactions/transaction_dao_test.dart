import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/investments/data/investment_dao.dart';
import 'package:finos_app/features/investments/domain/investment_contribution_mode.dart';
import 'package:finos_app/features/investments/domain/investment_instrument_type.dart';
import 'package:finos_app/features/investments/domain/investment_payout_frequency.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransactionDao', () {
    late AppDatabase database;
    late AccountDao accounts;
    late InvestmentDao investments;
    late TransactionDao dao;

    setUp(() {
      database = AppDatabase.inMemory();
      accounts = AccountDao(database);
      investments = InvestmentDao(database);
      dao = TransactionDao(database);
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
          type: AccountType.bank,
        ),
      );
      return id;
    }

    Future<String> seedInvestment(String id, {required String accountId}) async {
      await investments.insertOne(
        InvestmentsCompanion.insert(
          id: id,
          name: id,
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 100000,
          sourceAccountId: accountId,
          payoutAccountId: accountId,
          startDate: DateTime(2026, 1, 1),
          maturityDate: DateTime(2027, 1, 1),
          payoutFrequency: const InvestmentPayoutFrequency.atMaturity(),
        ),
      );
      return id;
    }

    Future<TransactionRow> seedTransaction(
      String id, {
      required String accountId,
      TransactionType type = TransactionType.expense,
      int amountMinor = 1000,
      String? destinationAccountId,
      String? categoryId,
      String? investmentId,
      DateTime? date,
    }) async {
      final row = TransactionRow(
        id: id,
        type: type,
        amountMinor: amountMinor,
        currency: 'BDT',
        accountId: accountId,
        destinationAccountId: destinationAccountId,
        categoryId: categoryId,
        investmentId: investmentId,
        date: date ?? DateTime(2026, 8, 10),
        description: '',
        createdAt: DateTime(2026, 8, 10),
        updatedAt: DateTime(2026, 8, 10),
      );
      await dao.insertOne(row.toCompanion(true));
      return row;
    }

    test('getById returns the matching row', () async {
      final source = await seedAccount('One');
      await seedTransaction('tx-1', accountId: source);
      await seedTransaction('tx-2', accountId: source);

      final row = await dao.getById('tx-2');
      expect(row, isNotNull);
      expect(row!.id, 'tx-2');
    });

    test('getById returns null when no row matches', () async {
      expect(await dao.getById('missing'), isNull);
    });

    test('getAll returns transactions ordered by date descending', () async {
      final source = await seedAccount('One');
      await seedTransaction(
        'tx-old',
        accountId: source,
        date: DateTime(2026, 1, 1),
      );
      await seedTransaction(
        'tx-new',
        accountId: source,
        date: DateTime(2026, 8, 10),
      );
      await seedTransaction(
        'tx-mid',
        accountId: source,
        date: DateTime(2026, 6, 15),
      );

      final rows = await dao.getAll();
      expect(rows.map((r) => r.id).toList(), ['tx-new', 'tx-mid', 'tx-old']);
    });

    test('updateOne replaces the row contents', () async {
      final source = await seedAccount('One');
      await seedTransaction('tx-1', accountId: source, amountMinor: 1000);

      final row = await dao.getById('tx-1');
      await dao.updateOne(row!.copyWith(amountMinor: 777777));

      final updated = await dao.getById('tx-1');
      expect(updated!.amountMinor, 777777);
    });

    test('deleteOne removes the row', () async {
      final source = await seedAccount('One');
      await seedTransaction('tx-1', accountId: source);

      await dao.deleteOne('tx-1');
      expect(await dao.getById('tx-1'), isNull);
    });

    group('balanceImpactFor', () {
      test('returns 0 for an account with no transactions', () async {
        await seedAccount('One');
        expect(await dao.balanceImpactFor('acct-One'), 0);
      });

      test('adds income and subtracts expenses', () async {
        final source = await seedAccount('One');
        await seedTransaction(
          'inc',
          accountId: source,
          type: TransactionType.income,
          amountMinor: 500000,
        );
        await seedTransaction(
          'exp',
          accountId: source,
          type: TransactionType.expense,
          amountMinor: 150000,
        );

        expect(await dao.balanceImpactFor(source), 350000);
      });

      test('accounts for transfers on both sides', () async {
        final source = await seedAccount('One');
        final destination = await seedAccount('Two');
        await seedTransaction(
          'trf',
          accountId: source,
          type: TransactionType.transfer,
          amountMinor: 200000,
          destinationAccountId: destination,
        );

        // Source loses the money, destination gains it.
        expect(await dao.balanceImpactFor(source), -200000);
        expect(await dao.balanceImpactFor(destination), 200000);
      });

      test('combines income, expenses, and transfers', () async {
        final source = await seedAccount('One');
        final destination = await seedAccount('Two');

        await seedTransaction(
          'salary',
          accountId: source,
          type: TransactionType.income,
          amountMinor: 1000000,
        );
        await seedTransaction(
          'rent',
          accountId: source,
          type: TransactionType.expense,
          amountMinor: 300000,
        );
        await seedTransaction(
          'to-budget',
          accountId: source,
          type: TransactionType.transfer,
          amountMinor: 100000,
          destinationAccountId: destination,
        );
        await seedTransaction(
          'food',
          accountId: destination,
          type: TransactionType.expense,
          amountMinor: 50000,
        );

        // Source: +1,000,000 −300,000 −100,000 = 600,000
        expect(await dao.balanceImpactFor(source), 600000);

        // Destination: +100,000 (transfer in) −50,000 = 50,000
        expect(await dao.balanceImpactFor(destination), 50000);
      });
    });

    group('balanceImpactForBefore', () {
      test('returns 0 for an account with no transactions', () async {
        await seedAccount('One');
        expect(
          await dao.balanceImpactForBefore('acct-One', DateTime(2026, 8, 10)),
          0,
        );
      });

      test('excludes transactions on or after the cutoff', () async {
        final source = await seedAccount('One');
        await seedTransaction(
          'before',
          accountId: source,
          type: TransactionType.expense,
          amountMinor: 100000,
          date: DateTime(2026, 8, 4),
        );
        await seedTransaction(
          'on-cutoff',
          accountId: source,
          type: TransactionType.expense,
          amountMinor: 200000,
          date: DateTime(2026, 8, 5),
        );
        await seedTransaction(
          'after',
          accountId: source,
          type: TransactionType.expense,
          amountMinor: 400000,
          date: DateTime(2026, 8, 6),
        );

        expect(
          await dao.balanceImpactForBefore(source, DateTime(2026, 8, 5)),
          -100000,
        );
      });

      test(
        'matches balanceImpactFor once the cutoff is in the future',
        () async {
          final source = await seedAccount('One');
          await seedTransaction(
            'inc',
            accountId: source,
            type: TransactionType.income,
            amountMinor: 500000,
            date: DateTime(2026, 8, 1),
          );
          await seedTransaction(
            'exp',
            accountId: source,
            type: TransactionType.expense,
            amountMinor: 150000,
            date: DateTime(2026, 8, 2),
          );

          expect(
            await dao.balanceImpactForBefore(source, DateTime(2100, 1, 1)),
            await dao.balanceImpactFor(source),
          );
        },
      );
    });

    group('totalsForAccountAndPeriod', () {
      test('returns zero totals for an account with no transactions', () async {
        await seedAccount('One');
        final totals = await dao.totalsForAccountAndPeriod(
          'acct-One',
          DateTime(2026, 8, 1),
          DateTime(2026, 9, 1),
        );

        expect(totals.incomeMinor, 0);
        expect(totals.expenseMinor, 0);
      });

      test('sums income and expense within the range', () async {
        final source = await seedAccount('One');
        await seedTransaction(
          'salary',
          accountId: source,
          type: TransactionType.income,
          amountMinor: 500000,
          date: DateTime(2026, 8, 5),
        );
        await seedTransaction(
          'rent',
          accountId: source,
          type: TransactionType.expense,
          amountMinor: 150000,
          date: DateTime(2026, 8, 10),
        );
        await seedTransaction(
          'outside-range',
          accountId: source,
          type: TransactionType.expense,
          amountMinor: 999999,
          date: DateTime(2026, 9, 1),
        );

        final totals = await dao.totalsForAccountAndPeriod(
          source,
          DateTime(2026, 8, 1),
          DateTime(2026, 9, 1),
        );

        expect(totals.incomeMinor, 500000);
        expect(totals.expenseMinor, 150000);
      });

      test('excludes another account\'s transactions', () async {
        final target = await seedAccount('One');
        final other = await seedAccount('Two');
        await seedTransaction(
          'in-target',
          accountId: target,
          type: TransactionType.income,
          amountMinor: 400000,
          date: DateTime(2026, 8, 5),
        );
        await seedTransaction(
          'in-other',
          accountId: other,
          type: TransactionType.income,
          amountMinor: 700000,
          date: DateTime(2026, 8, 5),
        );

        final totals = await dao.totalsForAccountAndPeriod(
          target,
          DateTime(2026, 8, 1),
          DateTime(2026, 9, 1),
        );

        expect(totals.incomeMinor, 400000);
      });

      test('excludes transfers', () async {
        final source = await seedAccount('One');
        final destination = await seedAccount('Two');
        await seedTransaction(
          'trf',
          accountId: source,
          type: TransactionType.transfer,
          amountMinor: 200000,
          destinationAccountId: destination,
          date: DateTime(2026, 8, 5),
        );

        final totals = await dao.totalsForAccountAndPeriod(
          source,
          DateTime(2026, 8, 1),
          DateTime(2026, 9, 1),
        );

        expect(totals.incomeMinor, 0);
        expect(totals.expenseMinor, 0);
      });
    });

    group('investmentTotalsByInvestment', () {
      test('returns an empty map when nothing is in range', () async {
        final result = await dao.investmentTotalsByInvestment(
          DateTime(2026, 8, 1),
          DateTime(2026, 9, 1),
        );

        expect(result, isEmpty);
      });

      test(
        'sums contributions and payouts per investment within the range',
        () async {
          final source = await seedAccount('One');
          await seedInvestment('inv-1', accountId: source);
          await seedInvestment('inv-2', accountId: source);
          await seedTransaction(
            'contrib-1',
            accountId: source,
            type: TransactionType.investmentContribution,
            amountMinor: 500000,
            investmentId: 'inv-1',
            date: DateTime(2026, 8, 5),
          );
          await seedTransaction(
            'payout-1',
            accountId: source,
            type: TransactionType.investmentPayout,
            amountMinor: 12000,
            investmentId: 'inv-1',
            date: DateTime(2026, 8, 10),
          );
          await seedTransaction(
            'contrib-2',
            accountId: source,
            type: TransactionType.investmentContribution,
            amountMinor: 300000,
            investmentId: 'inv-2',
            date: DateTime(2026, 8, 12),
          );
          await seedTransaction(
            'withdrawal-1',
            accountId: source,
            type: TransactionType.investmentWithdrawal,
            amountMinor: 40000,
            investmentId: 'inv-1',
            date: DateTime(2026, 8, 15),
          );
          await seedTransaction(
            'outside-range',
            accountId: source,
            type: TransactionType.investmentContribution,
            amountMinor: 999999,
            investmentId: 'inv-1',
            date: DateTime(2026, 9, 1),
          );

          final result = await dao.investmentTotalsByInvestment(
            DateTime(2026, 8, 1),
            DateTime(2026, 9, 1),
          );

          expect(result['inv-1']!.contributedMinor, 500000);
          expect(result['inv-1']!.payoutMinor, 12000);
          expect(result['inv-1']!.withdrawnMinor, 40000);
          expect(result['inv-2']!.contributedMinor, 300000);
          expect(result['inv-2']!.withdrawnMinor, 0);
          expect(result['inv-2']!.payoutMinor, 0);
        },
      );

      test('excludes ordinary transactions with no investment id', () async {
        final source = await seedAccount('One');
        await seedTransaction(
          'expense',
          accountId: source,
          type: TransactionType.expense,
          amountMinor: 1000,
          date: DateTime(2026, 8, 5),
        );

        final result = await dao.investmentTotalsByInvestment(
          DateTime(2026, 8, 1),
          DateTime(2026, 9, 1),
        );

        expect(result, isEmpty);
      });
    });
  });
}
