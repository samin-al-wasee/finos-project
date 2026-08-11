import '../../transactions/domain/period_totals.dart';

/// One category's share of a report period's expense.
class CategoryAmount {
  const CategoryAmount({required this.categoryId, required this.amountMinor});

  /// Null for expenses with no assigned category.
  final String? categoryId;
  final int amountMinor;
}

/// The data behind the Reports screen for one selected period
/// (docs/ROADMAP.md §8.4).
class ReportData {
  const ReportData({
    required this.totals,
    required this.previousTotals,
    required this.categorySpending,
  });

  /// Income/expense for the selected period.
  final PeriodTotals totals;

  /// Income/expense for the immediately preceding period, for comparison.
  final PeriodTotals previousTotals;

  /// This-period expense by category, highest first.
  final List<CategoryAmount> categorySpending;

  /// Percentage change in expense vs the previous period.
  ///
  /// Null when the previous period had zero expense — "changed by what
  /// percent from zero" is undefined, not infinite or zero, so callers must
  /// handle the absence explicitly rather than displaying a nonsense figure.
  double? get expenseChangePercent =>
      _percentChange(previousTotals.expenseMinor, totals.expenseMinor);

  /// Percentage change in income vs the previous period. See
  /// [expenseChangePercent] for why this is nullable.
  double? get incomeChangePercent =>
      _percentChange(previousTotals.incomeMinor, totals.incomeMinor);
}

double? _percentChange(int from, int to) {
  if (from == 0) return null;
  return (to - from) / from * 100;
}
