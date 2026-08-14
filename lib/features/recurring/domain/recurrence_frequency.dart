import 'package:drift/drift.dart';

import '../../budgets/domain/budget_period.dart' show dayStart;

/// How often a recurring transaction repeats (docs/DATA_MODEL.md §27).
///
/// [RecurrenceFrequency.custom] from the roadmap's sketch (an arbitrary
/// N-day/week/month interval) is deliberately not included — it needs its own
/// "every N ___" field and is a refinement on top of this, not required for
/// the feature to be useful.
///
/// [quarterly] was added for the Investments feature (docs/adr/009), whose
/// fixed-term instruments (e.g. Sanchayapatra) commonly pay profit every
/// three months — reused here rather than forked so both features share the
/// same tested date math.
enum RecurrenceFrequency { daily, weekly, monthly, quarterly, yearly }

/// Maps [RecurrenceFrequency] to its canonical uppercase storage value in the
/// database (`DAILY`, `WEEKLY`, `MONTHLY`, `QUARTERLY`, `YEARLY`).
class RecurrenceFrequencyConverter
    extends TypeConverter<RecurrenceFrequency, String> {
  const RecurrenceFrequencyConverter();

  static const Map<RecurrenceFrequency, String> _storage = {
    RecurrenceFrequency.daily: 'DAILY',
    RecurrenceFrequency.weekly: 'WEEKLY',
    RecurrenceFrequency.monthly: 'MONTHLY',
    RecurrenceFrequency.quarterly: 'QUARTERLY',
    RecurrenceFrequency.yearly: 'YEARLY',
  };

  @override
  RecurrenceFrequency fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown RecurrenceFrequency storage value: $fromDb');
  }

  @override
  String toSql(RecurrenceFrequency value) => _storage[value]!;
}

/// The next calendar date after [from] for a rule that repeats every
/// [frequency] (docs/DATA_MODEL.md §27).
///
/// Monthly and yearly clamp to the last valid day of the target month rather
/// than overflowing into the following one — a rule dated the 31st means "the
/// last day of the month" in a 30-day month, not "the 2nd or 3rd of next
/// month" (the naive result of adding a month to a `DateTime` directly).
DateTime nextOccurrence(DateTime from, RecurrenceFrequency frequency) {
  final day = dayStart(from);
  switch (frequency) {
    case RecurrenceFrequency.daily:
      return DateTime(day.year, day.month, day.day + 1);
    case RecurrenceFrequency.weekly:
      return DateTime(day.year, day.month, day.day + 7);
    case RecurrenceFrequency.monthly:
      return _addMonthsClamped(day, 1);
    case RecurrenceFrequency.quarterly:
      return _addMonthsClamped(day, 3);
    case RecurrenceFrequency.yearly:
      return _addMonthsClamped(day, 12);
  }
}

/// Adds [months] to [date], clamping the day-of-month to the last valid day
/// of the resulting month. [months] must be non-negative — this only ever
/// advances a recurrence forward in time.
DateTime _addMonthsClamped(DateTime date, int months) {
  final monthIndex = date.month - 1 + months;
  final targetYear = date.year + monthIndex ~/ 12;
  final targetMonth = monthIndex % 12 + 1;
  // Day 0 of the month after the target is the target month's last day.
  final daysInTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;
  final day = date.day > daysInTargetMonth ? daysInTargetMonth : date.day;
  return DateTime(targetYear, targetMonth, day);
}

/// User-facing label for a [RecurrenceFrequency].
String recurrenceFrequencyLabel(RecurrenceFrequency frequency) {
  switch (frequency) {
    case RecurrenceFrequency.daily:
      return 'Daily';
    case RecurrenceFrequency.weekly:
      return 'Weekly';
    case RecurrenceFrequency.monthly:
      return 'Monthly';
    case RecurrenceFrequency.quarterly:
      return 'Quarterly';
    case RecurrenceFrequency.yearly:
      return 'Yearly';
  }
}
