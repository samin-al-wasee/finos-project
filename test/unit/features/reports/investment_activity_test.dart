import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/investments/domain/investment_contribution_mode.dart';
import 'package:finos_app/features/investments/domain/investment_instrument_type.dart';
import 'package:finos_app/features/investments/domain/investment_payout_frequency.dart';
import 'package:finos_app/features/investments/domain/investment_period_totals.dart';
import 'package:finos_app/features/investments/domain/investment_status.dart';
import 'package:finos_app/features/reports/domain/investment_activity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [investmentActivityForReport] (docs/ROADMAP.md §8.4).
void main() {
  final timestamp = DateTime(2026, 8, 10);

  InvestmentRow investmentWith(
    String id, {
    InvestmentStatus status = InvestmentStatus.active,
  }) => InvestmentRow(
    id: id,
    name: id,
    instrumentType: InvestmentInstrumentType.fdr,
    contributionMode: InvestmentContributionMode.lumpSum,
    amountMinor: 100000,
    currency: 'BDT',
    sourceAccountId: 'acct',
    payoutAccountId: 'acct',
    startDate: timestamp,
    maturityDate: timestamp.add(const Duration(days: 365)),
    payoutFrequency: const InvestmentPayoutFrequency.atMaturity(),
    status: status,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  InvestmentActivity activityWith(
    String id, {
    InvestmentStatus status = InvestmentStatus.active,
    int contributedMinor = 0,
    int payoutMinor = 0,
  }) => InvestmentActivity(
    investment: investmentWith(id, status: status),
    totals: InvestmentPeriodTotals(
      contributedMinor: contributedMinor,
      payoutMinor: payoutMinor,
    ),
    previousTotals: const InvestmentPeriodTotals(
      contributedMinor: 0,
      payoutMinor: 0,
    ),
  );

  test('excludes archived investments', () {
    final active = activityWith('active', contributedMinor: 1000);
    final archived = activityWith(
      'archived',
      contributedMinor: 1000,
      status: InvestmentStatus.archived,
    );

    final result = investmentActivityForReport([active, archived]);

    expect(result, [active]);
  });

  test('excludes investments with no contribution or payout this period', () {
    final withActivity = activityWith('active', contributedMinor: 500);
    final withoutActivity = activityWith('idle');

    final result = investmentActivityForReport([
      withActivity,
      withoutActivity,
    ]);

    expect(result, [withActivity]);
  });

  test('keeps an investment with only a payout and no contribution', () {
    final payoutOnly = activityWith('payout', payoutMinor: 2000);

    final result = investmentActivityForReport([payoutOnly]);

    expect(result, [payoutOnly]);
  });

  test('preserves input order', () {
    final first = activityWith('first', contributedMinor: 100);
    final second = activityWith('second', payoutMinor: 200);

    final result = investmentActivityForReport([second, first]);

    expect(result.map((a) => a.investment.id), ['second', 'first']);
  });
}
