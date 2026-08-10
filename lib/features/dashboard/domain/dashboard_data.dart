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

/// Aggregated data rendered by the dashboard (FR-07).
class DashboardData {
  const DashboardData({
    required this.totalBalanceMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.accountBalances,
    required this.categorySpending,
    required this.recentTransactions,
  });

  final int totalBalanceMinor;
  final int incomeMinor;
  final int expenseMinor;
  final List<AccountBalance> accountBalances;

  /// This-period expense by category, highest first, capped at five so the
  /// dashboard stays a summary rather than a report (docs/UI_DESIGN.md §8).
  final List<CategorySpending> categorySpending;

  /// Newest transactions, capped at five (docs/UI_DESIGN.md §8).
  final List<TransactionRow> recentTransactions;

  int get netCashFlowMinor => incomeMinor - expenseMinor;
}
