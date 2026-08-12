import '../../budgets/domain/budget_period.dart';

/// The fixed calendar windows for a financial report (FR-07,
/// docs/ROADMAP.md §8.4): "This month vs last month" and "this year vs last
/// year" are the comparisons named in the roadmap. [CustomReportRange] covers
/// an arbitrary user-picked range alongside these.
enum ReportPeriod { thisMonth, lastMonth, thisYear, lastYear }

/// A report's selected window: either one of the fixed [ReportPeriod]s or an
/// arbitrary [CustomReportRange].
///
/// Each variant knows how to derive its own comparison window and labels, so
/// callers (the provider, the screen) work in terms of this type rather than
/// branching on which kind of selection is active.
sealed class ReportWindowSelection {
  const ReportWindowSelection();

  /// The calendar window this selection covers, relative to [reference].
  DateRange window({required DateTime reference});

  /// The window to compare against — the immediately preceding window of
  /// equal length.
  DateRange previousWindow({required DateTime reference});

  /// User-facing label for the selected window, e.g. "This month".
  String get label;

  /// Label for the comparison window, e.g. "vs previous month".
  String get comparisonLabel;
}

/// One of the fixed calendar periods.
class FixedReportPeriod extends ReportWindowSelection {
  const FixedReportPeriod(this.period);

  final ReportPeriod period;

  @override
  DateRange window({required DateTime reference}) =>
      reportWindow(period, reference: reference);

  @override
  DateRange previousWindow({required DateTime reference}) =>
      previousReportWindow(period, reference: reference);

  @override
  String get label => reportPeriodLabel(period);

  @override
  String get comparisonLabel => reportComparisonLabel(period);

  @override
  bool operator ==(Object other) =>
      other is FixedReportPeriod && other.period == period;

  @override
  int get hashCode => period.hashCode;
}

/// An arbitrary user-picked date range.
///
/// The comparison window is the immediately preceding range of the same
/// length — e.g. a 10-day custom range compares against the 10 days before
/// it — mirroring how the fixed periods compare against the equivalent prior
/// month/year.
class CustomReportRange extends ReportWindowSelection {
  const CustomReportRange(this.range);

  final DateRange range;

  @override
  DateRange window({required DateTime reference}) => range;

  @override
  DateRange previousWindow({required DateTime reference}) {
    final length = range.to.difference(range.from);
    return DateRange(from: range.from.subtract(length), to: range.from);
  }

  @override
  String get label => 'Custom range';

  @override
  String get comparisonLabel => 'vs previous period';

  @override
  bool operator ==(Object other) =>
      other is CustomReportRange && other.range == range;

  @override
  int get hashCode => range.hashCode;
}

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
