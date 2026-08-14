import '../../../core/database/app_database.dart';
import '../../investments/domain/investment_period_totals.dart';
import '../../investments/domain/investment_status.dart';

/// One investment's contribution/payout/withdrawal activity for a report
/// period, plus the immediately preceding period for comparison
/// (docs/ROADMAP.md §8.4, "Investment Activity").
///
/// Contribution, payout, and withdrawal are three separate non-negative
/// figures, not a single signed net the way [AccountCashFlow] shows — they
/// are all normal activity for the same investment in the same period, not
/// opposing directions of one flow.
class InvestmentActivity {
  const InvestmentActivity({
    required this.investment,
    required this.totals,
    required this.previousTotals,
  });

  final InvestmentRow investment;
  final InvestmentPeriodTotals totals;
  final InvestmentPeriodTotals previousTotals;
}

/// Selects and orders investments for the Investment Activity report.
///
/// Archived investments are excluded — this report is about current
/// activity. Investments with no contribution or payout this period are also
/// excluded, the same "only show what happened" rule
/// [accountCashFlowsForReport] already applies to accounts. The input order
/// (investments' natural creation order) is preserved rather than re-sorted.
List<InvestmentActivity> investmentActivityForReport(
  List<InvestmentActivity> all,
) {
  return all
      .where((a) => a.investment.status != InvestmentStatus.archived)
      .where(
        (a) =>
            a.totals.contributedMinor != 0 ||
            a.totals.payoutMinor != 0 ||
            a.totals.withdrawnMinor != 0,
      )
      .toList();
}
