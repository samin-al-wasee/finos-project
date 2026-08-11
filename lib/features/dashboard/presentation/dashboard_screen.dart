import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../accounts/domain/account_status.dart';
import '../../accounts/presentation/account_details_screen.dart';
import '../../accounts/presentation/account_form_screen.dart';
import '../../accounts/presentation/account_type_label.dart';
import '../../categories/presentation/category_icon.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../transactions/presentation/transaction_form_screen.dart';
import '../../transactions/presentation/transaction_tile.dart';
import '../domain/dashboard_data.dart';

/// Home tab content (FR-07).
///
/// Shows the financial overview: total balance, this-month income and expenses,
/// a combined budget-status summary, per-account balances, this-month spending
/// by category, and the five most recent transactions. Recomputes
/// automatically whenever accounts, budgets, or transactions change.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardDataProvider);
    final categories = ref.watch(categoriesStreamProvider);
    final categoriesById = {
      for (final c in categories.valueOrNull ?? const <CategoryRow>[]) c.id: c,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('FinOS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: dashboard.when(
        data: (data) => data.accountBalances.isEmpty
            ? const EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No accounts yet',
                message:
                    'Add your bank accounts, wallets, and cards to start '
                    'tracking where your money lives.',
                action: _AddAccountButton(),
              )
            : _DashboardBody(data: data, categoriesById: categoriesById),
        error: (e, _) => _ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(dashboardDataProvider),
        ),
        loading: () => const _LoadingState(),
      ),
    );
  }
}

/// Scrollable overview: hero total, monthly summary, accounts, recent activity.
class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data, required this.categoriesById});

  final DashboardData data;
  final Map<String, CategoryRow> categoriesById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final accountNames = {
      for (final ab in data.accountBalances) ab.account.id: ab.account.name,
    };

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _TotalBalanceCard(totalBalanceMinor: data.totalBalanceMinor),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Income',
                amountMinor: data.incomeMinor,
                color: colors.income,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: _SummaryCard(
                label: 'Expenses',
                amountMinor: data.expenseMinor,
                color: colors.expense,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Net this month ${formatMinorUnits(data.netCashFlowMinor)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: data.netCashFlowMinor >= 0 ? colors.income : colors.expense,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (data.budgetStatus != null) ...[
          _BudgetStatusCard(status: data.budgetStatus!),
          const SizedBox(height: AppSpacing.lg),
        ] else
          const SizedBox(height: AppSpacing.lg),
        const _SectionHeader(title: 'Accounts'),
        for (final accountBalance in data.accountBalances)
          _AccountBalanceTile(accountBalance: accountBalance),
        if (data.categorySpending.isNotEmpty) ...[
          const _SectionHeader(title: 'Spending by category'),
          for (final spending in data.categorySpending)
            _CategorySpendingTile(
              spending: spending,
              category: categoriesById[spending.categoryId],
              totalExpenseMinor: data.expenseMinor,
            ),
        ],
        const _SectionHeader(title: 'Recent transactions'),
        if (data.recentTransactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'No transactions yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.mutedText,
              ),
            ),
          )
        else
          for (final row in data.recentTransactions)
            TransactionTile(
              key: ValueKey(row.id),
              transaction: row,
              accountName: accountNames[row.accountId] ?? row.accountId,
              destinationAccountName: row.destinationAccountId == null
                  ? null
                  : accountNames[row.destinationAccountId] ??
                        row.destinationAccountId,
              categoryName: categoriesById[row.categoryId]?.name,
              categoryIconKey: categoriesById[row.categoryId]?.icon,
              onTap: () => _openEdit(context, row),
            ),
      ],
    );
  }

  void _openEdit(BuildContext context, TransactionRow row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionFormScreen(initial: row),
      ),
    );
  }
}

/// The hero card showing the total balance across all accounts.
class _TotalBalanceCard extends StatelessWidget {
  const _TotalBalanceCard({required this.totalBalanceMinor});

  final int totalBalanceMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Balance', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              formatMinorUnits(totalBalanceMinor),
              style: theme.textTheme.headlineMedium,
              key: const ValueKey('totalBalance'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact income/expense summary card.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amountMinor,
    required this.color,
  });

  final String label;
  final int amountMinor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              formatMinorUnits(amountMinor),
              style: theme.textTheme.titleLarge?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single-card summary of every active budget (FR-07).
///
/// Deliberately a summary, not a duplicate of the Budgets tab's per-category
/// detail: one bar for combined spend against combined limit, plus a line
/// naming how many budgets are near or over their limit — never color alone
/// (AGENTS.md §21).
class _BudgetStatusCard extends StatelessWidget {
  const _BudgetStatusCard({required this.status});

  final BudgetStatusSummary status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final color = status.exceededCount > 0
        ? colors.error
        : status.nearLimitCount > 0
        ? colors.warning
        : colors.success;
    final remaining = status.remainingMinor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Budgets', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: status.usedFraction.clamp(0.0, 1.0),
                minHeight: AppSpacing.sm,
                backgroundColor: colors.border,
                color: color,
                semanticsLabel: 'Combined budget used',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              remaining >= 0
                  ? '${formatMinorUnits(remaining)} remaining'
                  : '${formatMinorUnits(remaining.abs())} over budget',
              style: theme.textTheme.bodyMedium,
            ),
            if (status.exceededCount > 0 || status.nearLimitCount > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _statusLine(status),
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _statusLine(BudgetStatusSummary status) {
    final parts = <String>[
      if (status.exceededCount > 0) '${status.exceededCount} over limit',
      if (status.nearLimitCount > 0) '${status.nearLimitCount} near limit',
    ];
    return parts.join(', ');
  }
}

/// A section label ("Accounts", "Recent transactions").
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FinosColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: colors.mutedText),
      ),
    );
  }
}

/// One account row showing its computed current balance.
class _AccountBalanceTile extends StatelessWidget {
  const _AccountBalanceTile({required this.accountBalance});

  final AccountBalance accountBalance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final account = accountBalance.account;
    final archived = account.status == AccountStatus.archived;

    return ListTile(
      leading: CircleAvatar(child: Icon(accountTypeIcon(account.type))),
      title: Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        formatMinorUnits(
          accountBalance.balanceMinor,
          symbol: currencySymbol(account.currency),
        ),
        style: theme.textTheme.titleSmall?.copyWith(
          color: archived ? colors.mutedText : null,
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AccountDetailsScreen(accountId: account.id),
        ),
      ),
    );
  }
}

/// One category's row in the "Spending by category" section.
///
/// The bar shows this category's share of *total expense for the period*, not
/// a budget limit — there may be no budget for the category at all. The share
/// is naturally within 0–1 since it is one part of the same total, so no
/// clamping is needed (unlike a budget bar, which can exceed its limit).
class _CategorySpendingTile extends StatelessWidget {
  const _CategorySpendingTile({
    required this.spending,
    required this.category,
    required this.totalExpenseMinor,
  });

  final CategorySpending spending;
  final CategoryRow? category;
  final int totalExpenseMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final share = totalExpenseMinor <= 0
        ? 0.0
        : spending.amountMinor / totalExpenseMinor;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      // A screen reader announces this row as one statement — "Groceries,
      // ৳500, Groceries spending" — rather than three disjoint stops for the
      // icon-adjacent name, the amount, and the bar (docs/UI_DESIGN.md §43).
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  categoryIcon(category?.icon ?? 'label'),
                  size: 18,
                  color: colors.mutedText,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    category?.name ?? 'Uncategorized',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  formatMinorUnits(spending.amountMinor),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.expense,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: share,
                minHeight: AppSpacing.sm,
                backgroundColor: colors.border,
                color: colors.expense,
                semanticsLabel: '${category?.name ?? 'Uncategorized'} spending',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The button inside the empty state, kept as its own widget so the empty
/// state stays const.
class _AddAccountButton extends StatelessWidget {
  const _AddAccountButton();

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AccountFormScreen()),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Add account'),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxxl),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      message: message,
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    );
  }
}
