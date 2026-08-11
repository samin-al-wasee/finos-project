import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/reports/domain/report_period.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [reportWindow] and [previousReportWindow] — the calendar-based
/// windows behind the Reports screen (docs/ROADMAP.md §8.4).
void main() {
  group('reportWindow', () {
    test('thisMonth is the current calendar month', () {
      final window = reportWindow(
        ReportPeriod.thisMonth,
        reference: DateTime(2026, 8, 15),
      );
      expect(window, DateRange(from: DateTime(2026, 8), to: DateTime(2026, 9)));
    });

    test('lastMonth is the previous calendar month', () {
      final window = reportWindow(
        ReportPeriod.lastMonth,
        reference: DateTime(2026, 8, 15),
      );
      expect(window, DateRange(from: DateTime(2026, 7), to: DateTime(2026, 8)));
    });

    test('lastMonth rolls under the year boundary from January', () {
      final window = reportWindow(
        ReportPeriod.lastMonth,
        reference: DateTime(2026, 1, 15),
      );
      expect(
        window,
        DateRange(from: DateTime(2025, 12), to: DateTime(2026, 1)),
      );
    });

    test('thisYear is the current calendar year', () {
      final window = reportWindow(
        ReportPeriod.thisYear,
        reference: DateTime(2026, 8, 15),
      );
      expect(window, DateRange(from: DateTime(2026), to: DateTime(2027)));
    });

    test('lastYear is the previous calendar year', () {
      final window = reportWindow(
        ReportPeriod.lastYear,
        reference: DateTime(2026, 8, 15),
      );
      expect(window, DateRange(from: DateTime(2025), to: DateTime(2026)));
    });
  });

  group('previousReportWindow', () {
    test('thisMonth compares against the month before it', () {
      final previous = previousReportWindow(
        ReportPeriod.thisMonth,
        reference: DateTime(2026, 8, 15),
      );
      expect(
        previous,
        DateRange(from: DateTime(2026, 7), to: DateTime(2026, 8)),
      );
    });

    test('lastMonth compares against the month before that', () {
      final previous = previousReportWindow(
        ReportPeriod.lastMonth,
        reference: DateTime(2026, 8, 15),
      );
      expect(
        previous,
        DateRange(from: DateTime(2026, 6), to: DateTime(2026, 7)),
      );
    });

    test('thisYear compares against the year before it', () {
      final previous = previousReportWindow(
        ReportPeriod.thisYear,
        reference: DateTime(2026, 8, 15),
      );
      expect(previous, DateRange(from: DateTime(2025), to: DateTime(2026)));
    });

    test('lastYear compares against the year before that', () {
      final previous = previousReportWindow(
        ReportPeriod.lastYear,
        reference: DateTime(2026, 8, 15),
      );
      expect(previous, DateRange(from: DateTime(2024), to: DateTime(2025)));
    });

    test('a January reference rolls the month comparison under correctly', () {
      final previous = previousReportWindow(
        ReportPeriod.thisMonth,
        reference: DateTime(2026, 1, 15),
      );
      expect(
        previous,
        DateRange(from: DateTime(2025, 12), to: DateTime(2026, 1)),
      );
    });
  });

  group('labels', () {
    test('reportPeriodLabel names every period', () {
      expect(reportPeriodLabel(ReportPeriod.thisMonth), 'This month');
      expect(reportPeriodLabel(ReportPeriod.lastMonth), 'Last month');
      expect(reportPeriodLabel(ReportPeriod.thisYear), 'This year');
      expect(reportPeriodLabel(ReportPeriod.lastYear), 'Last year');
    });

    test('reportComparisonLabel groups by month/year granularity', () {
      expect(
        reportComparisonLabel(ReportPeriod.thisMonth),
        reportComparisonLabel(ReportPeriod.lastMonth),
      );
      expect(
        reportComparisonLabel(ReportPeriod.thisYear),
        reportComparisonLabel(ReportPeriod.lastYear),
      );
      expect(
        reportComparisonLabel(ReportPeriod.thisMonth),
        isNot(reportComparisonLabel(ReportPeriod.thisYear)),
      );
    });
  });
}
