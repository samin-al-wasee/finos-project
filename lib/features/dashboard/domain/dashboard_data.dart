import '../../../core/database/app_database.dart';

/// An account with its computed current balance
/// (opening balance + net balance impact).
class AccountBalance {
  const AccountBalance({required this.account, required this.balanceMinor});

  final FinancialAccountRow account;
  final int balanceMinor;
}

/// One category's share of this-period expense (FR-07).
///
/// [categoryId] is `null` for expenses with no assigned category, shown as
/// "Uncategorized" rather than dropped from the breakdown.
class CategorySpending {
  const CategorySpending({required this.categoryId, required this.amountMinor});

  final String? categoryId;
  final int amountMinor;
}

/// A single-card summary of active budgets for the dashboard (FR-07).
///
/// Deliberately an aggregate, not a duplicate of the Budgets tab's per-category
/// detail: total limit and spending across every active budget for its own
/// current window, plus how many are near or over their limit. Health is
/// exposed as plain counts rather than a health enum so the dashboard stays
/// free of a dependency on the budgets feature's domain types.
class BudgetStatusSummary {
  const BudgetStatusSummary({
    required this.limitMinor,
    required this.spentMinor,
    required this.budgetCount,
    required this.nearLimitCount,
    required this.exceededCount,
  });

  final int limitMinor;
  final int spentMinor;
  final int budgetCount;
  final int nearLimitCount;
  final int exceededCount;

  /// Limit minus spending. Negative once spending has passed the combined
  /// limit — the same convention the per-budget progress uses.
  int get remainingMinor => limitMinor - spentMinor;

  /// Spending as a fraction of the limit. Guards against a zero limit, which
  /// cannot happen for any single budget (validation rejects it) but could in
  /// principle arise from a summary with no budgets.
  double get usedFraction => limitMinor <= 0 ? 0 : spentMinor / limitMinor;
}

/// Aggregated data rendered by the dashboard (FR-07).
class DashboardData {
  const DashboardData({
    required this.totalBalanceMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.accountBalances,
    required this.categorySpending,
    required this.budgetStatus,
    required this.recentTransactions,
    required this.transactionCountThisPeriod,
  });

  final int totalBalanceMinor;
  final int incomeMinor;
  final int expenseMinor;
  final List<AccountBalance> accountBalances;

  /// This-period expense by category, highest first, capped at five so the
  /// dashboard stays a summary rather than a report (docs/UI_DESIGN.md §8).
  final List<CategorySpending> categorySpending;

  /// Summary across every active budget, or `null` when there are none to
  /// summarise — the section is hidden rather than shown empty.
  final BudgetStatusSummary? budgetStatus;

  /// Newest transactions, capped at five (docs/UI_DESIGN.md §8) — the
  /// Recent Activity summary card shows only the first of these as a
  /// preview, never the whole list.
  final List<TransactionRow> recentTransactions;

  /// How many transactions fall inside this same period as [incomeMinor]/
  /// [expenseMinor] — a plain in-memory count, not a new query.
  final int transactionCountThisPeriod;

  int get netCashFlowMinor => incomeMinor - expenseMinor;
}
