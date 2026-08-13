import '../../../core/database/app_database.dart';

/// A credit-card account's statement cycle, together with everything derived
/// from its billing details and current balance (docs/DATA_MODEL.md §60,
/// ADR-005).
///
/// Nothing here is stored: it is recomputed at read time from
/// [CreditCardDetailsRow] and the account's balance, so it can never disagree
/// with the transactions behind it — the same rule ADR-004 applies to a
/// loan's outstanding amount.
class CreditCardCycle {
  const CreditCardCycle({
    required this.details,
    required this.currentBalanceMinor,
    required this.previousStatementDate,
    required this.previousStatementBalanceMinor,
  });

  /// The stored billing details.
  final CreditCardDetailsRow details;

  /// The account's live balance (opening balance + net transaction impact).
  /// Negative means money is owed; positive means a credit sits on the card.
  final int currentBalanceMinor;

  /// The most recent statement close on or before today.
  final DateTime previousStatementDate;

  /// The account's balance as of [previousStatementDate] — locked in, and
  /// unaffected by spending in the current, still-open cycle.
  final int previousStatementBalanceMinor;

  int get creditLimitMinor => details.creditLimitMinor;

  /// What is currently owed. Clamped at zero: a positive balance means a
  /// credit sits on the card, not negative debt.
  int get outstandingMinor => _debtFrom(currentBalanceMinor);

  /// Credit limit minus what is currently owed. Clamped at zero: an account
  /// over its limit does not report negative available credit.
  int get availableCreditMinor {
    final available = creditLimitMinor - outstandingMinor;
    return available < 0 ? 0 : available;
  }

  /// What was owed as of the last statement close — the amount
  /// [paymentDueDate] applies to.
  int get previousStatementDebtMinor =>
      _debtFrom(previousStatementBalanceMinor);

  /// The next statement close after [previousStatementDate].
  DateTime get nextStatementDate =>
      nextStatementDateAfter(previousStatementDate, details.statementDay);

  /// When payment on [previousStatementDebtMinor] is due.
  DateTime get paymentDueDate =>
      previousStatementDate.add(Duration(days: details.paymentDueOffsetDays));

  static int _debtFrom(int balanceMinor) =>
      balanceMinor < 0 ? -balanceMinor : 0;
}

/// Returns the last valid calendar day for [year]/[month].
///
/// Day 0 of the following month is always the last day of this one, so this
/// works for every month without a special case for February/leap years.
int _lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// The statement date for [year]/[month] with [statementDay] clamped to that
/// month's last valid day — so day 31 resolves to the 28th/29th/30th in a
/// shorter month, instead of overflowing into the next month the way the
/// plain [DateTime] constructor would.
DateTime _clampedStatementDate(int year, int month, int statementDay) {
  final lastDay = _lastDayOfMonth(year, month);
  final day = statementDay < lastDay ? statementDay : lastDay;
  return DateTime(year, month, day);
}

/// The most recent statement close on or before [today], for a card whose
/// statement closes on [statementDay] (1–31) of each month.
DateTime statementDateOnOrBefore(DateTime today, int statementDay) {
  final day = _dayStart(today);
  final thisMonth = _clampedStatementDate(day.year, day.month, statementDay);
  if (!thisMonth.isAfter(day)) return thisMonth;
  // This month's statement hasn't closed yet — fall back to last month's.
  return _clampedStatementDate(day.year, day.month - 1, statementDay);
}

/// The next statement close strictly after [previousStatementDate] — one
/// calendar month later, clamped the same way. [DateTime.month] normalizes
/// month 13 into January of the following year (and negative months
/// normalize backwards the same way), so year rollover needs no special case.
DateTime nextStatementDateAfter(
  DateTime previousStatementDate,
  int statementDay,
) {
  return _clampedStatementDate(
    previousStatementDate.year,
    previousStatementDate.month + 1,
    statementDay,
  );
}

/// Midnight (local) on [date]'s calendar day — statement cycles are calendar
/// dates, so the clock time must not decide which cycle "today" falls in
/// (docs/DATA_MODEL.md §42).
DateTime _dayStart(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}
