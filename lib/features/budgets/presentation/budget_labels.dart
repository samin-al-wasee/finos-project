import 'package:flutter/material.dart';

import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../categories/presentation/category_icon.dart';
import '../domain/budget_period.dart';
import '../domain/budget_progress.dart';
import '../domain/budget_scope.dart';

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

/// User-facing label for a [BudgetScopeType].
///
/// Used by the create form's scope-type selector.
String budgetScopeTypeLabel(BudgetScopeType type) {
  switch (type) {
    case BudgetScopeType.singleCategory:
      return 'Single category';
    case BudgetScopeType.multiCategory:
      return 'Multiple categories';
    case BudgetScopeType.uncategorized:
      return 'Uncategorised spending';
    case BudgetScopeType.wholeAccount:
      return 'Whole account';
  }
}

/// What a budget covers, for display in place of a single category name
/// (docs/adr/007-flexible-budget-scope.md) — a category name for
/// [SingleCategoryScope], a count for [MultiCategoryScope], or a fixed phrase
/// for the two category-less scopes.
String budgetScopeLabel(BudgetProgress progress) => switch (progress.scope) {
  SingleCategoryScope() => progress.categories.single.name,
  MultiCategoryScope() => '${progress.categories.length} categories',
  UncategorizedScope() => 'Uncategorised',
  WholeAccountScope() => 'Whole account',
};

/// The icon representing what a budget covers, mirroring [budgetScopeLabel].
IconData budgetScopeIcon(BudgetProgress progress) => switch (progress.scope) {
  SingleCategoryScope() => categoryIcon(progress.categories.single.icon),
  MultiCategoryScope() => Icons.category_outlined,
  UncategorizedScope() => Icons.help_outline,
  WholeAccountScope() => Icons.account_balance_wallet_outlined,
};

/// Describes [progress]'s carried-in amount, or `null` when there is nothing
/// to show (docs/adr/008-budget-rollover.md).
///
/// The carry is folded into [BudgetProgress.limitMinor] silently, so this
/// exists to make that fold visible rather than leaving a ৳10,000 budget
/// showing ৳12,300 with no explanation: a positive carry reads as "included",
/// a negative one as a deficit.
String? budgetCarryInLabel(BudgetProgress progress) {
  final carry = progress.carriedInMinor;
  if (carry == 0) return null;
  final symbol = currencySymbol(progress.budget.currency);
  return carry > 0
      ? 'Includes ${formatMinorUnits(carry, symbol: symbol)} carried in'
      : '${formatMinorUnits(-carry, symbol: symbol)} carried over as a '
            'deficit';
}
