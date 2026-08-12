import '../../budgets/domain/budget_period.dart' show dayStart;
import 'recurrence_frequency.dart';

/// How many occurrence dates [dueOccurrences] returns for one rule, even if
/// more are actually due — a daily recurrence left untouched for months
/// should not turn into hundreds of individually-confirmable rows
/// (docs/DATA_MODEL.md §26).
const maxDueOccurrences = 30;

/// A hard backstop on how many dates [dueOccurrences] will ever compute,
/// counted or not — independent of [maxDueOccurrences], so a bug that makes
/// [nextOccurrence] fail to advance can never loop unbounded.
const _maxOccurrencesConsidered = 10000;

/// Every occurrence date due by [asOf] for a rule whose next occurrence is
/// [from], oldest first.
///
/// [totalCount] is the true number due, which may exceed
/// [DueOccurrences.dates]'s length — capping is never silent, so a caller can
/// always tell the user there is a larger backlog than what is shown.
class DueOccurrences {
  const DueOccurrences({required this.dates, required this.totalCount});

  /// Occurrence dates to actually show, oldest first, capped at
  /// [maxDueOccurrences].
  final List<DateTime> dates;

  /// The true number of occurrences due — `>= dates.length`.
  final int totalCount;

  bool get isCapped => totalCount > dates.length;
}

/// Computes [DueOccurrences] for a rule that repeats every [frequency],
/// starting from [from] (typically the rule's stored `next_occurrence`) and
/// due no later than [asOf], stopping at [endDate] if given.
DueOccurrences dueOccurrences({
  required DateTime from,
  required RecurrenceFrequency frequency,
  required DateTime asOf,
  DateTime? endDate,
}) {
  final asOfDay = dayStart(asOf);
  final endDay = endDate == null ? null : dayStart(endDate);

  final dates = <DateTime>[];
  var totalCount = 0;
  var current = dayStart(from);
  while (!current.isAfter(asOfDay) &&
      (endDay == null || !current.isAfter(endDay)) &&
      totalCount < _maxOccurrencesConsidered) {
    totalCount++;
    if (dates.length < maxDueOccurrences) dates.add(current);
    current = nextOccurrence(current, frequency);
  }
  return DueOccurrences(dates: dates, totalCount: totalCount);
}
