/// Contribution, payout, and withdrawal sums for one investment within a
/// report period (docs/ROADMAP.md §8.4, "Investment Activity";
/// docs/adr/010-investment-early-withdrawal.md).
class InvestmentPeriodTotals {
  const InvestmentPeriodTotals({
    required this.contributedMinor,
    required this.payoutMinor,
    this.withdrawnMinor = 0,
  });

  final int contributedMinor;
  final int payoutMinor;

  /// Principal returned early this period, via `INVESTMENT_WITHDRAWAL`
  /// transactions — distinct from [payoutMinor], which is profit.
  final int withdrawnMinor;
}
