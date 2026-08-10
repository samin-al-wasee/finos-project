import '../../../core/database/app_database.dart';

/// An account with its computed current balance
/// (opening balance + net balance impact).
class AccountBalance {
  const AccountBalance({required this.account, required this.balanceMinor});

  final FinancialAccountRow account;
  final int balanceMinor;
}

/// Aggregated data rendered by the dashboard (FR-07).
class DashboardData {
  const DashboardData({
    required this.totalBalanceMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.accountBalances,
    required this.recentTransactions,
  });

  final int totalBalanceMinor;
  final int incomeMinor;
  final int expenseMinor;
  final List<AccountBalance> accountBalances;

  /// Newest transactions, capped at five (docs/UI_DESIGN.md §8).
  final List<TransactionRow> recentTransactions;

  int get netCashFlowMinor => incomeMinor - expenseMinor;
}
