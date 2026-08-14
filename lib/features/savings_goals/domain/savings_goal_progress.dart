import '../../../core/database/app_database.dart';
import 'savings_goal_status.dart';

/// A savings goal together with everything derived from its
/// contributions/withdrawals (docs/adr/011-savings-goals.md).
///
/// ```text
/// current amount = max(0, contributed − withdrawn)
/// ```
class SavingsGoalProgress {
  const SavingsGoalProgress({
    required this.goal,
    required this.contributedMinor,
    required this.withdrawnMinor,
  });

  /// The stored savings goal record.
  final SavingsGoalRow goal;

  /// Total contributed so far, in integer minor units.
  final int contributedMinor;

  /// Total withdrawn so far, in integer minor units.
  final int withdrawnMinor;

  /// What's currently saved toward the goal. Clamped at zero: a withdrawal
  /// can never be recorded for more than what's currently saved (enforced in
  /// `SavingsGoalController.withdraw`), so a negative value here would mean
  /// corrupt data, never a real deficit.
  int get currentAmountMinor {
    final remaining = contributedMinor - withdrawnMinor;
    return remaining < 0 ? 0 : remaining;
  }

  /// Fraction of the target saved so far — `0.75` means three quarters
  /// there. Clamped at 1: saving beyond the target is ordinary (a buffer,
  /// or rounding up), so this never reports more than "fully there."
  ///
  /// Guards against a non-positive target, which validation rejects, so
  /// this can never divide by zero.
  double get progressFraction {
    if (goal.targetAmountMinor <= 0) return 0;
    final fraction = currentAmountMinor / goal.targetAmountMinor;
    return fraction > 1 ? 1 : fraction;
  }

  /// True once the current amount has reached the target.
  ///
  /// A derived fact, not a status: reaching it does not change [goal]'s
  /// stored `status` or stop further contributions
  /// (docs/adr/011-savings-goals.md §3).
  bool get isAchieved => currentAmountMinor >= goal.targetAmountMinor;

  /// Whether the goal is archived (a stored lifecycle state, not a derived
  /// milestone).
  bool get isArchived => goal.status == SavingsGoalStatus.archived;

  /// True when the goal isn't yet achieved and its deadline has passed.
  ///
  /// [now] is injectable so tests are not tied to the clock. A goal with no
  /// deadline is never overdue.
  bool isOverdue({DateTime? now}) {
    final deadline = goal.deadlineDate;
    if (deadline == null || isAchieved) return false;
    final today = _dayStart(now ?? DateTime.now());
    return _dayStart(deadline).isBefore(today);
  }

  /// The largest withdrawal that may still be recorded against this goal.
  ///
  /// Over-withdrawal is rejected (docs/adr/011-savings-goals.md §3), so this
  /// is exactly the current amount saved.
  int get maxWithdrawalMinor => currentAmountMinor;

  /// Midnight on [date]'s calendar day; the deadline is a calendar date, so
  /// the clock time must not decide whether a goal is overdue
  /// (docs/DATA_MODEL.md §42).
  static DateTime _dayStart(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
