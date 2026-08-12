import 'package:finos_app/features/reports/domain/report_data.dart';
import 'package:finos_app/features/transactions/domain/period_totals.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [ReportData]'s derived comparison percentages.
void main() {
  ReportData report({
    int incomeMinor = 0,
    int expenseMinor = 0,
    int previousIncomeMinor = 0,
    int previousExpenseMinor = 0,
  }) {
    return ReportData(
      totals: PeriodTotals(
        incomeMinor: incomeMinor,
        expenseMinor: expenseMinor,
      ),
      previousTotals: PeriodTotals(
        incomeMinor: previousIncomeMinor,
        expenseMinor: previousExpenseMinor,
      ),
      categorySpending: const [],
      accountCashFlows: const [],
    );
  }

  group('expenseChangePercent', () {
    test('is positive when expense increased', () {
      final data = report(expenseMinor: 12000, previousExpenseMinor: 10000);
      expect(data.expenseChangePercent, closeTo(20.0, 0.001));
    });

    test('is negative when expense decreased', () {
      final data = report(expenseMinor: 8000, previousExpenseMinor: 10000);
      expect(data.expenseChangePercent, closeTo(-20.0, 0.001));
    });

    test('is zero when expense is unchanged', () {
      final data = report(expenseMinor: 10000, previousExpenseMinor: 10000);
      expect(data.expenseChangePercent, closeTo(0.0, 0.001));
    });

    test('is null when the previous period had no expense', () {
      final data = report(expenseMinor: 5000, previousExpenseMinor: 0);
      expect(data.expenseChangePercent, isNull);
    });

    test('is null when both periods have no expense', () {
      final data = report(expenseMinor: 0, previousExpenseMinor: 0);
      expect(data.expenseChangePercent, isNull);
    });
  });

  group('incomeChangePercent', () {
    test('is positive when income increased', () {
      final data = report(incomeMinor: 150000, previousIncomeMinor: 100000);
      expect(data.incomeChangePercent, closeTo(50.0, 0.001));
    });

    test('is null when the previous period had no income', () {
      final data = report(incomeMinor: 50000, previousIncomeMinor: 0);
      expect(data.incomeChangePercent, isNull);
    });
  });
}
