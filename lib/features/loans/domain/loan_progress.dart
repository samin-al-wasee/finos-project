import '../../../core/database/app_database.dart';
import 'loan_direction.dart';
import 'loan_status.dart';

/// Where a loan stands (docs/DATA_MODEL.md §33).
///
/// Derived at read time, never stored, so it cannot disagree with the repayments
/// behind it (ADR-004).
enum LoanStanding {
  /// Still owing, and either not yet due or with no due date at all.
  outstanding,

  /// Still owing, and the due date has passed.
  overdue,

  /// Fully repaid.
  paid,
}

/// A loan together with everything derived from its repayments.
///
/// ```text
/// outstanding = principal − Σ(repayments)
/// ```
class LoanProgress {
  const LoanProgress({
    required this.loan,
    required this.repaidMinor,
    required this.repaymentCount,
  });

  /// The stored loan record.
  final LoanRow loan;

  /// Total repaid so far, in integer minor units.
  final int repaidMinor;

  /// How many repayments have been recorded.
  final int repaymentCount;

  /// Which way the loan runs.
  LoanDirection get direction => loan.type;

  /// The original amount.
  int get principalMinor => loan.principalMinor;

  /// What is still owed. Clamped at zero: overpayment is rejected on the way in,
  /// so a negative value would mean corrupt data rather than a real credit.
  int get outstandingMinor {
    final remaining = principalMinor - repaidMinor;
    return remaining < 0 ? 0 : remaining;
  }

  /// Fraction of the principal repaid — `0.75` means three quarters settled.
  ///
  /// Guards against a non-positive principal, which validation rejects, so this
  /// can never divide by zero.
  double get repaidFraction {
    if (principalMinor <= 0) return 0;
    final fraction = repaidMinor / principalMinor;
    return fraction > 1 ? 1 : fraction;
  }

  /// True once nothing is left to repay.
  bool get isPaid => outstandingMinor == 0;

  /// Whether the loan is archived (a stored lifecycle state, not a standing).
  bool get isArchived => loan.status == LoanStatus.archived;

  /// True when money is still owed and the due date has passed.
  ///
  /// [now] is injectable so tests are not tied to the clock. A loan with no due
  /// date is never overdue.
  bool isOverdue({DateTime? now}) {
    final due = loan.dueDate;
    if (due == null || isPaid) return false;
    final today = _dayStart(now ?? DateTime.now());
    return _dayStart(due).isBefore(today);
  }

  /// The loan's derived standing.
  LoanStanding standing({DateTime? now}) {
    if (isPaid) return LoanStanding.paid;
    if (isOverdue(now: now)) return LoanStanding.overdue;
    return LoanStanding.outstanding;
  }

  /// The largest repayment that may still be recorded against this loan.
  ///
  /// Overpayment is rejected (docs/DATA_MODEL.md §36), so this is exactly the
  /// outstanding amount.
  int get maxRepaymentMinor => outstandingMinor;

  /// Midnight on [date]'s calendar day; due dates are calendar dates, so the
  /// clock time must not decide whether a loan is overdue
  /// (docs/DATA_MODEL.md §42).
  static DateTime _dayStart(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
