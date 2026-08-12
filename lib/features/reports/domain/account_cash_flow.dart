import '../../../core/database/app_database.dart';
import '../../accounts/domain/account_status.dart';
import '../../transactions/domain/period_totals.dart';

/// One account's income/expense for a report period, plus the immediately
/// preceding period for comparison (docs/ROADMAP.md §8.4, "Account Cash
/// Flow").
class AccountCashFlow {
  const AccountCashFlow({
    required this.account,
    required this.totals,
    required this.previousTotals,
  });

  final FinancialAccountRow account;
  final PeriodTotals totals;
  final PeriodTotals previousTotals;
}

/// Selects and orders accounts for the Cash Flow by Account report.
///
/// Archived accounts are excluded — this report is about current activity.
/// Accounts with no income or expense this period are also excluded, the
/// same "only show what happened" behavior `categorySpending` already gets
/// for free from its `GROUP BY` query. The input order (accounts' natural
/// creation order) is preserved rather than re-sorted; there is no risk
/// ranking here the way there is for budgets.
List<AccountCashFlow> accountCashFlowsForReport(List<AccountCashFlow> all) {
  return all
      .where((flow) => flow.account.status == AccountStatus.active)
      .where(
        (flow) => flow.totals.incomeMinor != 0 || flow.totals.expenseMinor != 0,
      )
      .toList();
}
