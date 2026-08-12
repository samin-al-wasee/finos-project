import 'package:drift/drift.dart';

/// A half-open calendar range `[from, to)` — `from` is included, `to` is not.
///
/// Half-open ranges avoid the classic off-by-one at period boundaries: a
/// transaction dated exactly on `to` belongs to the *next* period, never to two
/// periods at once. Both bounds are midnight-local calendar dates
/// (docs/DATA_MODEL.md §42).
class DateRange {
  const DateRange({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  /// Whether [date] falls inside the range, comparing calendar days.
  bool contains(DateTime date) {
    final day = dayStart(date);
    return !day.isBefore(from) && day.isBefore(to);
  }

  /// The last calendar day inside the range (i.e. [to] minus one day).
  ///
  /// Useful for display: users read "Aug 1 – Aug 31", not "Aug 1 – Sep 1".
  DateTime get lastDay => DateTime(to.year, to.month, to.day - 1);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'DateRange($from → $to)';
}

/// The recurrence shape of a budget's spending window (docs/DATA_MODEL.md §23).
enum BudgetPeriod { weekly, monthly, yearly, custom }

/// Maps [BudgetPeriod] to its canonical uppercase storage value in the database
/// (`WEEKLY`, `MONTHLY`, `YEARLY`, `CUSTOM` — docs/DATA_MODEL.md §23).
class BudgetPeriodConverter extends TypeConverter<BudgetPeriod, String> {
  const BudgetPeriodConverter();

  static const Map<BudgetPeriod, String> _storage = {
    BudgetPeriod.weekly: 'WEEKLY',
    BudgetPeriod.monthly: 'MONTHLY',
    BudgetPeriod.yearly: 'YEARLY',
    BudgetPeriod.custom: 'CUSTOM',
  };

  @override
  BudgetPeriod fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown BudgetPeriod storage value: $fromDb');
  }

  @override
  String toSql(BudgetPeriod value) => _storage[value]!;
}

/// Returns the spending window a budget is measured over at [reference].
///
/// The recurring periods derive their window from the calendar rather than from
/// [startDate], so a monthly budget always means "this calendar month" no matter
/// which day of the month it was created on:
///
/// * [BudgetPeriod.weekly] — Monday through Sunday of the reference week
/// * [BudgetPeriod.monthly] — the 1st through the last day of the reference
///   month
/// * [BudgetPeriod.yearly] — Jan 1 through Dec 31 of the reference year
/// * [BudgetPeriod.custom] — exactly [startDate] through [endDate] inclusive
///
/// [startDate] records when the budget takes effect and is the authoritative
/// window start for [BudgetPeriod.custom]. [endDate] is required for custom
/// periods and ignored otherwise.
///
/// Throws [ArgumentError] for a custom period without an [endDate].
DateRange budgetWindow(
  BudgetPeriod period, {
  required DateTime reference,
  required DateTime startDate,
  DateTime? endDate,
}) {
  switch (period) {
    case BudgetPeriod.weekly:
    case BudgetPeriod.monthly:
    case BudgetPeriod.yearly:
      return shiftedBudgetWindow(period, reference: reference, offset: 0)!;
    case BudgetPeriod.custom:
      if (endDate == null) {
        throw ArgumentError('A custom budget period needs an end date');
      }
      final start = dayStart(startDate);
      final end = dayStart(endDate);
      // endDate is an inclusive calendar day, so the half-open bound is the
      // following midnight.
      return DateRange(
        from: start,
        to: DateTime(end.year, end.month, end.day + 1),
      );
  }
}

/// The [period] window [offset] periods away from the one containing
/// [reference] — `0` is the current window, `-1` the immediately preceding
/// one, `-2` the one before that, and so on (docs/ROADMAP.md §8.3, budget
/// history).
///
/// Returns `null` for [BudgetPeriod.custom]: a custom window is a single
/// fixed range tied to the budget's own start/end dates, not a recurring
/// shape, so it has no "previous period" to compute.
DateRange? shiftedBudgetWindow(
  BudgetPeriod period, {
  required DateTime reference,
  required int offset,
}) {
  final day = dayStart(reference);

  switch (period) {
    case BudgetPeriod.weekly:
      // DateTime.weekday is 1 (Monday) through 7 (Sunday).
      final start = DateTime(
        day.year,
        day.month,
        day.day - (day.weekday - 1) + offset * 7,
      );
      return DateRange(
        from: start,
        to: DateTime(start.year, start.month, start.day + 7),
      );
    case BudgetPeriod.monthly:
      return DateRange(
        from: DateTime(day.year, day.month + offset),
        // Month 13 normalises to January of the next year (and negative
        // months normalise backwards the same way).
        to: DateTime(day.year, day.month + offset + 1),
      );
    case BudgetPeriod.yearly:
      return DateRange(
        from: DateTime(day.year + offset),
        to: DateTime(day.year + offset + 1),
      );
    case BudgetPeriod.custom:
      return null;
  }
}

/// Returns midnight (local) on [date]'s calendar day.
///
/// Budget windows are calendar ranges, so the time component is deliberately
/// discarded (docs/DATA_MODEL.md §42). Dates are constructed via the [DateTime]
/// constructor rather than [Duration] arithmetic so daylight-saving shifts never
/// move a boundary onto the wrong day.
DateTime dayStart(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}
