import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/reports/domain/account_cash_flow.dart';
import 'package:finos_app/features/transactions/domain/period_totals.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [accountCashFlowsForReport] (docs/ROADMAP.md §8.4).
void main() {
  final timestamp = DateTime(2026, 8, 10);

  FinancialAccountRow accountWith(
    String id, {
    AccountStatus status = AccountStatus.active,
  }) => FinancialAccountRow(
    id: id,
    name: id,
    type: AccountType.bank,
    currency: 'BDT',
    openingBalanceMinor: 0,
    createdAt: timestamp,
    updatedAt: timestamp,
    status: status,
  );

  AccountCashFlow flowWith(
    String id, {
    AccountStatus status = AccountStatus.active,
    int incomeMinor = 0,
    int expenseMinor = 0,
  }) => AccountCashFlow(
    account: accountWith(id, status: status),
    totals: PeriodTotals(incomeMinor: incomeMinor, expenseMinor: expenseMinor),
    previousTotals: const PeriodTotals(incomeMinor: 0, expenseMinor: 0),
  );

  test('excludes archived accounts', () {
    final active = flowWith('active', incomeMinor: 1000);
    final archived = flowWith(
      'archived',
      incomeMinor: 1000,
      status: AccountStatus.archived,
    );

    final result = accountCashFlowsForReport([active, archived]);

    expect(result, [active]);
  });

  test('excludes accounts with no activity this period', () {
    final withActivity = flowWith('active', expenseMinor: 500);
    final withoutActivity = flowWith('idle');

    final result = accountCashFlowsForReport([withActivity, withoutActivity]);

    expect(result, [withActivity]);
  });

  test('preserves input order', () {
    final first = flowWith('first', incomeMinor: 100);
    final second = flowWith('second', expenseMinor: 200);

    final result = accountCashFlowsForReport([second, first]);

    expect(result.map((f) => f.account.id), ['second', 'first']);
  });
}
