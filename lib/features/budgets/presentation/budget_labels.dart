import '../../../core/formatting/date.dart';
import '../domain/budget_period.dart';
import '../domain/budget_progress.dart';

/// User-facing label for a [BudgetPeriod].
///
/// Presentation-only text; the domain enum stays free of UI concerns.
String budgetPeriodLabel(BudgetPeriod period) {
  switch (period) {
    case BudgetPeriod.weekly:
      return 'Weekly';
    case BudgetPeriod.monthly:
      return 'Monthly';
    case BudgetPeriod.yearly:
      return 'Yearly';
    case BudgetPeriod.custom:
      return 'Custom';
  }
}

/// Describes the window a budget is currently measured over, e.g.
/// `Aug 1, 2026 – Aug 31, 2026`.
///
/// Shows the inclusive last day rather than the half-open upper bound, because
/// "Aug 1 – Sep 1" reads as though September is included when it isn't.
String budgetWindowLabel(DateRange window) =>
    '${formatDate(window.from)} – ${formatDate(window.lastDay)}';

/// Short textual state for a budget, so its health never depends on colour
/// alone (docs/UI_DESIGN.md §20–§21, AGENTS.md §21).
String budgetHealthLabel(BudgetHealth health) {
  switch (health) {
    case BudgetHealth.underLimit:
      return 'On track';
    case BudgetHealth.nearLimit:
      return 'Near limit';
    case BudgetHealth.exceeded:
      return 'Over budget';
  }
}
