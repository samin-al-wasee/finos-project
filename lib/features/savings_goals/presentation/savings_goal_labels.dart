import '../domain/savings_goal_progress.dart';

/// Textual standing, so a savings goal's state never depends on colour alone
/// (AGENTS.md §21).
String savingsGoalStandingLabel(SavingsGoalProgress progress) {
  if (progress.isArchived) return 'Archived';
  if (progress.isAchieved) return 'Achieved';
  if (progress.isOverdue()) return 'Overdue';
  return 'Active';
}
