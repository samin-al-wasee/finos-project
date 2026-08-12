import '../../budgets/domain/budget_period.dart';

/// Number of trailing calendar months shown in the Monthly Spending report,
/// including the month containing the reference date.
const int monthlySpendingMonthCount = 6;

/// One calendar month's total expense, for the Monthly Spending report
/// (docs/ROADMAP.md §8.4).
class MonthlyExpense {
  const MonthlyExpense({required this.month, required this.expenseMinor});

  /// The first day of the calendar month this total covers.
  final DateTime month;
  final int expenseMinor;
}

/// The trailing [monthlySpendingMonthCount] calendar-month windows for the
/// Monthly Spending report, oldest first, ending with the month containing
/// [reference].
///
/// Deliberately independent of the report screen's period selector: a trend
/// across several months doesn't fit the "this period vs previous period"
/// shape the other report sections share, so this always shows the same
/// trailing window regardless of what's selected there.
List<DateRange> monthlySpendingWindows({required DateTime reference}) {
  final day = dayStart(reference);
  return [
    for (var i = monthlySpendingMonthCount - 1; i >= 0; i--)
      DateRange(
        from: DateTime(day.year, day.month - i),
        to: DateTime(day.year, day.month - i + 1),
      ),
  ];
}
