import '../../budgets/domain/budget_progress.dart';
import '../../budgets/domain/budget_status.dart';

/// Orders budgets for the Budget Performance report (docs/ROADMAP.md §8.4).
///
/// Each budget keeps its own natural current window rather than being forced
/// into the report screen's This/Last Month/Year selector — a budget's period
/// (weekly/monthly/yearly/custom) is independent of that selector, and
/// re-deriving "spend for an arbitrary calendar window" for a budget whose
/// own period doesn't align with it would invent an undefined calculation
/// (AGENTS.md §11). [all] is expected to already carry each budget's current
/// window, e.g. from `budgetProgressProvider`.
///
/// Archived budgets are excluded — this report is about current standing.
/// The rest are sorted so budgets needing attention surface first: exceeded,
/// then near limit, then under limit; ties within a group break by higher
/// [BudgetProgress.usedFraction] first.
List<BudgetProgress> budgetsForPerformanceReport(List<BudgetProgress> all) {
  final active = all
      .where((progress) => progress.budget.status == BudgetStatus.active)
      .toList();

  active.sort((a, b) {
    final healthOrder = _riskRank(a.health).compareTo(_riskRank(b.health));
    if (healthOrder != 0) return healthOrder;
    return b.usedFraction.compareTo(a.usedFraction);
  });

  return active;
}

int _riskRank(BudgetHealth health) {
  switch (health) {
    case BudgetHealth.exceeded:
      return 0;
    case BudgetHealth.nearLimit:
      return 1;
    case BudgetHealth.underLimit:
      return 2;
  }
}
