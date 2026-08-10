/// Sums of income and expense within a period (docs/DATA_MODEL.md §17).
///
/// Transfers are deliberately excluded — they move money between accounts and
/// are neither income nor expense.
class PeriodTotals {
  const PeriodTotals({required this.incomeMinor, required this.expenseMinor});

  final int incomeMinor;
  final int expenseMinor;

  /// Income minus expense for the period; negative when spending exceeded
  /// income.
  int get netCashFlowMinor => incomeMinor - expenseMinor;
}
