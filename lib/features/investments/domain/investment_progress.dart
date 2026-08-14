import '../../../core/database/app_database.dart';
import '../../recurring/domain/due_occurrences.dart';
import '../../recurring/domain/recurrence_frequency.dart';
import 'investment_contribution_mode.dart';
import 'investment_status.dart';

/// An investment together with everything derived from its transactions
/// (docs/adr/009-investment-accounting.md).
///
/// ```text
/// contributed = Σ(contributions)
/// payout received = Σ(payouts)
/// ```
///
/// Whether the instrument has *matured* is derived from [InvestmentRow.maturityDate]
/// at read time, never stored — the same precedent `LoanProgress.standing`
/// sets for a loan's paid/overdue status (ADR-004).
class InvestmentProgress {
  const InvestmentProgress({
    required this.investment,
    required this.contributedMinor,
    required this.payoutReceivedMinor,
    this.latestPayoutDate,
  });

  /// The stored investment record.
  final InvestmentRow investment;

  /// Total contributed so far, in integer minor units.
  final int contributedMinor;

  /// Total paid out so far (periodic profit plus, once matured, principal),
  /// in integer minor units.
  final int payoutReceivedMinor;

  /// The date of the most recent payout transaction, if any.
  final DateTime? latestPayoutDate;

  /// Whether the investment is archived (a stored lifecycle state).
  bool get isArchived => investment.status == InvestmentStatus.archived;

  /// True once the instrument's maturity date has arrived.
  ///
  /// [now] is injectable so tests are not tied to the clock.
  bool isMatured({DateTime? now}) {
    final today = _dayStart(now ?? DateTime.now());
    return !_dayStart(investment.maturityDate).isAfter(today);
  }

  /// Whether the instrument's final maturity payout is still owed.
  ///
  /// True once matured, not archived, and no payout has been recorded on or
  /// after the maturity date yet — a payout dated before maturity is
  /// periodic profit, not the maturity settlement, so it does not satisfy
  /// this. There is no separate stored "matured" flag: this is derived fresh
  /// every time from [latestPayoutDate], so correcting a maturity payout
  /// entered in error is just deleting that transaction, never undoing a
  /// status.
  bool isMaturityPayoutDue({DateTime? now}) {
    if (isArchived || !isMatured(now: now)) return false;
    return !isSettled;
  }

  /// True once the investment's maturity payout has actually been recorded —
  /// a payout transaction dated on or after [InvestmentRow.maturityDate].
  ///
  /// This, not [payoutReceivedMinor], is what should zero out an
  /// investment's net-worth contribution: a *periodic* payout (e.g.
  /// Sanchayapatra's quarterly profit) is new profit credited to the payout
  /// account, not a return of principal, so it must not reduce the locked
  /// value this getter guards — only the maturity settlement, which actually
  /// returns the principal, does (docs/adr/009-investment-accounting.md).
  bool get isSettled {
    final latest = latestPayoutDate;
    return latest != null &&
        !_dayStart(latest).isBefore(_dayStart(investment.maturityDate));
  }

  /// Due recurring contribution occurrences (DPS only).
  ///
  /// `null` when this instrument doesn't take recurring contributions, is
  /// archived, or has no contribution schedule (a lump-sum instrument has
  /// nothing left to contribute after creation).
  DueOccurrences? dueContributions({DateTime? now}) {
    if (isArchived) return null;
    if (investment.contributionMode != InvestmentContributionMode.recurring) {
      return null;
    }
    final nextDue = investment.nextContributionDue;
    if (nextDue == null) return null;
    return dueOccurrences(
      from: nextDue,
      frequency: RecurrenceFrequency.monthly,
      asOf: now ?? DateTime.now(),
      endDate: investment.maturityDate,
    );
  }

  /// Due periodic payout occurrences (e.g. Sanchayapatra's quarterly profit).
  ///
  /// `null` when this instrument pays only at maturity, is archived, or has
  /// already matured — periodic payouts stop at maturity, where
  /// [isMaturityPayoutDue] takes over instead.
  DueOccurrences? duePayouts({DateTime? now}) {
    if (isArchived || isMatured(now: now)) return null;
    final frequency = investment.payoutFrequency.periodic;
    if (frequency == null) return null;
    final nextDue = investment.nextPayoutDue;
    if (nextDue == null) return null;
    return dueOccurrences(
      from: nextDue,
      frequency: frequency,
      asOf: now ?? DateTime.now(),
      endDate: investment.maturityDate,
    );
  }

  /// Midnight on [date]'s calendar day; maturity is a calendar date, so the
  /// clock time must not decide whether an investment has matured
  /// (docs/DATA_MODEL.md §42).
  static DateTime _dayStart(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
