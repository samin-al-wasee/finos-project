// Date formatting helpers for user-facing labels.
//
// Dates are treated as calendar dates (docs/DATA_MODEL.md §41): the time
// component is ignored when comparing "today" vs "yesterday" so a transaction
// recorded late at night doesn't shift to another day because of the clock.

const List<String> _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats [date] as a compact calendar date, e.g. `Aug 10, 2026`.
///
/// Uses the local timezone of the device for the day/month — the financial
/// event date is a calendar date, not a UTC timestamp.
String formatDate(DateTime date) {
  final local = date.toLocal();
  final month = _monthNames[local.month - 1];
  return '$month ${local.day}, ${local.year}';
}

/// Returns a friendly label for [date] relative to [now].
///
/// * "Today" when [date] is on the same calendar day as [now]
/// * "Yesterday" when [date] is the day before [now]
/// * otherwise a compact calendar date via [formatDate]
///
/// [now] defaults to the current time; callers can pass a fixed value for
/// deterministic tests.
String dateLabel(DateTime date, {DateTime? now}) {
  final day = _dayStart(date);
  final today = _dayStart(now ?? DateTime.now());

  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  return formatDate(date);
}

/// Returns the start (midnight) of [date]'s calendar day in the local timezone.
DateTime _dayStart(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}
