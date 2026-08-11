import '../../budgets/domain/budget_period.dart';

/// The selectable windows for a financial report (FR-07, docs/ROADMAP.md §8.4).
///
/// Deliberately a small fixed set rather than an arbitrary date-range picker —
/// "This month vs last month" and "this year vs last year" are the comparisons
/// named in the roadmap; a custom range is a later refinement, not V1-of-this-
/// feature scope.
enum ReportPeriod { thisMonth, lastMonth, thisYear, lastYear }

/// The calendar window a [ReportPeriod] covers, relative to [reference].
///
/// Mirrors `budgetWindow`'s calendar-based approach (docs/DATA_MODEL.md §42):
/// windows are calendar months/years, not rolling 30/365-day windows.
DateRange reportWindow(ReportPeriod period, {required DateTime reference}) {
  final day = dayStart(reference);
  switch (period) {
    case ReportPeriod.thisMonth:
      return DateRange(
        from: DateTime(day.year, day.month),
        to: DateTime(day.year, day.month + 1),
      );
    case ReportPeriod.lastMonth:
      return DateRange(
        from: DateTime(day.year, day.month - 1),
        to: DateTime(day.year, day.month),
      );
    case ReportPeriod.thisYear:
      return DateRange(from: DateTime(day.year), to: DateTime(day.year + 1));
    case ReportPeriod.lastYear:
      return DateRange(from: DateTime(day.year - 1), to: DateTime(day.year));
  }
}

/// The window immediately preceding [reportWindow], for a "vs previous
/// period" comparison — the month before, or the year before.
DateRange previousReportWindow(
  ReportPeriod period, {
  required DateTime reference,
}) {
  final window = reportWindow(period, reference: reference);
  switch (period) {
    case ReportPeriod.thisMonth:
    case ReportPeriod.lastMonth:
      return DateRange(
        from: DateTime(window.from.year, window.from.month - 1),
        to: window.from,
      );
    case ReportPeriod.thisYear:
    case ReportPeriod.lastYear:
      return DateRange(from: DateTime(window.from.year - 1), to: window.from);
  }
}

/// User-facing label for a [ReportPeriod].
String reportPeriodLabel(ReportPeriod period) {
  switch (period) {
    case ReportPeriod.thisMonth:
      return 'This month';
    case ReportPeriod.lastMonth:
      return 'Last month';
    case ReportPeriod.thisYear:
      return 'This year';
    case ReportPeriod.lastYear:
      return 'Last year';
  }
}

/// Label for the comparison window, e.g. "vs last month" / "vs last year".
String reportComparisonLabel(ReportPeriod period) {
  switch (period) {
    case ReportPeriod.thisMonth:
    case ReportPeriod.lastMonth:
      return 'vs previous month';
    case ReportPeriod.thisYear:
    case ReportPeriod.lastYear:
      return 'vs previous year';
  }
}
