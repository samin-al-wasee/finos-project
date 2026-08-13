import '../../../core/database/app_database.dart';
import 'budget_period.dart';

/// Total spending in the half-open window `[from, to)`, in integer minor
/// units.
///
/// Deliberately window-only — no `categoryId` parameter. [rolloverCarryInMinor]
/// never needs to know *what* a budget's limit applies to, only how much was
/// spent in a given window, so callers close over a budget's already-resolved
/// `BudgetScope` and the scope-aware dispatcher
/// (`lib/app/providers.dart`'s `_spentMinorForScope`) to build this. That is
/// what lets rollover work uniformly across every scope type introduced by
/// docs/adr/007-flexible-budget-scope.md with no special-casing here
/// (docs/adr/008-budget-rollover.md).
typedef SpendLookup = Future<int> Function(DateTime from, DateTime to);

/// Same bound as `budgetHistoryLength` (lib/app/providers.dart) — deliberately
/// kept in lockstep so the carry a user sees is always fully explained by the
/// periods visible on the History screen (docs/adr/008-budget-rollover.md).
const int rolloverLookbackLimit = 6;

/// The amount carried into [budget]'s period containing [reference], from up
/// to [rolloverLookbackLimit] trailing periods (docs/ROADMAP.md §8.3,
/// docs/adr/008-budget-rollover.md).
///
/// Returns `0` when rollover is off, or for [BudgetPeriod.custom] (a one-off
/// range has no "next period" to carry into, and `shiftedBudgetWindow`
/// already returns `null` for it).
///
/// The walk is iterative, oldest-eligible-period-first, and bounded to at
/// most [rolloverLookbackLimit] calls to [spentBetween] — never a naive
/// unbounded recursion back to the budget's `start_date`. Each period's own
/// remainder — positive (unspent) or negative (overspent) — folds forward
/// into the next period's effective limit, unclamped, so a deficit
/// genuinely compounds rather than resetting at zero.
Future<int> rolloverCarryInMinor({
  required BudgetRow budget,
  required DateTime reference,
  required SpendLookup spentBetween,
}) async {
  if (!budget.rolloverEnabled) return 0;
  if (budget.period == BudgetPeriod.custom) return 0;

  final startDay = dayStart(budget.startDate);
  final eligibleOffsets = <int>[];
  for (var offset = -rolloverLookbackLimit; offset <= -1; offset++) {
    final window = shiftedBudgetWindow(
      budget.period,
      reference: reference,
      offset: offset,
    )!;
    if (window.to.isAfter(startDay)) eligibleOffsets.add(offset);
  }

  var carry = 0;
  for (final offset in eligibleOffsets) {
    // oldest first
    final window = shiftedBudgetWindow(
      budget.period,
      reference: reference,
      offset: offset,
    )!;
    // window-only — caller closes over scope.
    final spent = await spentBetween(window.from, window.to);
    carry = budget.amountMinor + carry - spent; // that period's own remainder
  }
  return carry;
}
