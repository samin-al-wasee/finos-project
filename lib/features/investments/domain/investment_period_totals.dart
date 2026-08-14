/// Contribution and payout sums for one investment within a report period
/// (docs/ROADMAP.md §8.4, "Investment Activity").
class InvestmentPeriodTotals {
  const InvestmentPeriodTotals({
    required this.contributedMinor,
    required this.payoutMinor,
  });

  final int contributedMinor;
  final int payoutMinor;
}
