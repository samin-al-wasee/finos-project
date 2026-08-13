import '../../../core/database/app_database.dart';
import 'budget_period.dart';
import 'budget_scope.dart';

/// How a budget is doing against its limit (docs/DATA_MODEL.md §25).
///
/// Derived at read time from actual spending — never stored, so it can never
/// disagree with the underlying transactions.
enum BudgetHealth { underLimit, nearLimit, exceeded }

/// A budget together with the spending measured against it for one window.
///
/// Spending is the sum of EXPENSE transactions inside the budget's scope that
/// fall inside [window]. Income and transfers are excluded: a transfer moves the
/// user's own money between accounts and is not spending
/// (docs/DATA_MODEL.md §17, §24).
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.scope,
    required this.categories,
    required this.window,
    required this.spentMinor,
    this.carriedInMinor = 0,
  });

  /// The stored budget record.
  final BudgetRow budget;

  /// What this budget's limit applies to (docs/adr/007-flexible-budget-scope.md).
  final BudgetScope scope;

  /// The categories [scope] resolves to, for display — 0 ([UncategorizedScope],
  /// [WholeAccountScope]), 1 ([SingleCategoryScope]), or many
  /// ([MultiCategoryScope]).
  final List<CategoryRow> categories;

  /// The calendar window spending was measured over.
  final DateRange window;

  /// Total spending inside [window], in integer minor units.
  final int spentMinor;

  /// The amount carried in from prior periods, in integer minor units
  /// (docs/adr/008-budget-rollover.md). Positive for a carried-forward
  /// surplus, negative for a carried-forward deficit, `0` when rollover is
  /// off or inapplicable (e.g. [budget.period] is [BudgetPeriod.custom]).
  final int carriedInMinor;

  /// Fraction of the limit at or above which a budget counts as "near limit"
  /// (docs/DATA_MODEL.md §25).
  static const double nearLimitThreshold = 0.8;

  /// The budget's effective spending limit, in integer minor units: its own
  /// limit plus whatever carried in from prior periods
  /// (docs/adr/008-budget-rollover.md). `budget.amountMinor` remains directly
  /// reachable for anyone who wants the "own" (un-rolled) limit.
  int get limitMinor => budget.amountMinor + carriedInMinor;

  /// Limit minus spending. Negative once the budget is exceeded, which is what
  /// lets the UI say "৳500 over budget" rather than clamping to zero.
  int get remainingMinor => limitMinor - spentMinor;

  /// Spending as a fraction of the limit — `0.75` means 75% used.
  ///
  /// Not clamped: a value above `1.0` means the budget is over its limit. Guards
  /// against a non-positive limit (which validation rejects) so this can never
  /// divide by zero.
  double get usedFraction => limitMinor <= 0 ? 0 : spentMinor / limitMinor;

  /// True once spending has passed the limit.
  bool get isExceeded => spentMinor > limitMinor;

  /// The derived health of this budget.
  ///
  /// Spending exactly equal to the limit is [BudgetHealth.nearLimit], not
  /// exceeded — the user has spent their plan, but not overspent it.
  BudgetHealth get health {
    if (isExceeded) return BudgetHealth.exceeded;
    if (usedFraction >= nearLimitThreshold) return BudgetHealth.nearLimit;
    return BudgetHealth.underLimit;
  }
}
