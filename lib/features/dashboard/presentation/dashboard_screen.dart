import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../accounts/presentation/account_form_screen.dart';
import '../../accounts/presentation/accounts_list_screen.dart';
import '../../budgets/presentation/budgets_list_screen.dart';
import '../../categories/presentation/category_icon.dart';
import '../../investments/presentation/investments_list_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../transactions/presentation/transactions_list_screen.dart';
import '../domain/dashboard_data.dart';

/// Home tab content (FR-07).
///
/// Every section below the balance is a single summary card — never a
/// per-item list like the Accounts or Transactions tabs already show —
/// tappable through to that tab's full screen for detail. The balance card
/// stays pinned at a constant height while everything else scrolls under it.
/// Recomputes automatically whenever accounts, budgets, or transactions
/// change.
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

/// Pinned total balance, then every other section as a tappable summary
/// card, scrolling underneath.
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

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _BalanceHeaderDelegate(
            totalBalanceMinor: data.totalBalanceMinor,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      label: 'Income',
                      amountMinor: data.incomeMinor,
                      color: colors.income,
                      onTap: () => _openReports(context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _SummaryCard(
                      label: 'Expenses',
                      amountMinor: data.expenseMinor,
                      color: colors.expense,
                      onTap: () => _openReports(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Net this month ${formatMinorUnits(data.netCashFlowMinor)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: data.netCashFlowMinor >= 0
                      ? colors.income
                      : colors.expense,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (data.budgetStatus != null) ...[
                _BudgetStatusCard(
                  status: data.budgetStatus!,
                  onTap: () => _openBudgets(context),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _AccountsSummaryCard(
                accountCount: data.accountBalances.length,
                onTap: () => _openAccounts(context),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (data.investmentsSummary != null) ...[
                _InvestmentsSummaryCard(
                  summary: data.investmentsSummary!,
                  onTap: () => _openInvestments(context),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (data.categorySpending.isNotEmpty) ...[
                _CategorySpendingSummaryCard(
                  topSpending: data.categorySpending.first,
                  topCategory:
                      categoriesById[data.categorySpending.first.categoryId],
                  moreCount: data.categorySpending.length - 1,
                  totalExpenseMinor: data.expenseMinor,
                  onTap: () => _openReports(context),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _RecentActivityCard(
                transactionCount: data.transactionCountThisPeriod,
                latest: data.recentTransactions.isEmpty
                    ? null
                    : data.recentTransactions.first,
                accountNames: accountNames,
                categoriesById: categoriesById,
                onTap: () => _openTransactions(context),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  void _openAccounts(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AccountsListScreen()));
  }

  void _openTransactions(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TransactionsListScreen()),
    );
  }

  void _openBudgets(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const BudgetsListScreen()));
  }

  void _openInvestments(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const InvestmentsListScreen()),
    );
  }

  void _openReports(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReportsScreen()));
  }
}

/// Keeps the total balance card visible at a constant height while the rest
/// of the dashboard scrolls underneath it — the single most important
/// figure (docs/UI_DESIGN.md §3.2), not the whole hero group.
class _BalanceHeaderDelegate extends SliverPersistentHeaderDelegate {
  _BalanceHeaderDelegate({required this.totalBalanceMinor});

  final int totalBalanceMinor;

  // A generous fixed height — enough for the card's label + amount at
  // default text scale, with margin to spare.
  static const double _height = 160;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: _TotalBalanceCard(totalBalanceMinor: totalBalanceMinor),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _BalanceHeaderDelegate oldDelegate) =>
      oldDelegate.totalBalanceMinor != totalBalanceMinor;
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Total Balance', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatMinorUnits(totalBalanceMinor),
                style: theme.textTheme.headlineMedium,
                key: const ValueKey('totalBalance'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact income/expense summary card, tapping through to Reports.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amountMinor,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int amountMinor;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
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
      ),
    );
  }
}

/// A single-card summary of every active budget (FR-07), tapping through to
/// the Budgets tab.
///
/// Deliberately a summary, not a duplicate of the Budgets tab's per-category
/// detail: one bar for combined spend against combined limit, plus a line
/// naming how many budgets are near or over their limit — never color alone
/// (AGENTS.md §21).
class _BudgetStatusCard extends StatelessWidget {
  const _BudgetStatusCard({required this.status, required this.onTap});

  final BudgetStatusSummary status;
  final VoidCallback onTap;

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
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
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

/// Aggregate summary of every account — a count, not a per-account list
/// (that's the Accounts tab's job) — tapping through to it.
class _AccountsSummaryCard extends StatelessWidget {
  const _AccountsSummaryCard({required this.accountCount, required this.onTap});

  final int accountCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: colors.mutedText,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Accounts', style: theme.textTheme.labelLarge),
                    Text(
                      '$accountCount ${accountCount == 1 ? 'account' : 'accounts'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aggregate summary of every active investment — a count and combined
/// invested total, not the per-investment list (that's the Investments
/// screen's job) — tapping through to it.
class _InvestmentsSummaryCard extends StatelessWidget {
  const _InvestmentsSummaryCard({required this.summary, required this.onTap});

  final InvestmentsSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(Icons.savings_outlined, color: colors.mutedText),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Investments', style: theme.textTheme.labelLarge),
                    Text(
                      '${summary.investmentCount} '
                      '${summary.investmentCount == 1 ? 'investment' : 'investments'} · '
                      '${formatMinorUnits(summary.totalInvestedMinor)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aggregate summary of this period's spending by category: the single
/// biggest category, not the full per-category list (that lives on
/// Reports) — tapping through to it.
class _CategorySpendingSummaryCard extends StatelessWidget {
  const _CategorySpendingSummaryCard({
    required this.topSpending,
    required this.topCategory,
    required this.moreCount,
    required this.totalExpenseMinor,
    required this.onTap,
  });

  final CategorySpending topSpending;
  final CategoryRow? topCategory;
  final int moreCount;
  final int totalExpenseMinor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final share = totalExpenseMinor <= 0
        ? 0.0
        : topSpending.amountMinor / totalExpenseMinor;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Spending by category', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              // Merged into one screen-reader statement, the same reason the
              // Transactions/Budgets per-row equivalents do (docs/UI_DESIGN.md
              // §43) — the icon, name, and amount are one fact, not three.
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          categoryIcon(topCategory?.icon ?? 'label'),
                          size: 18,
                          color: colors.mutedText,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            topCategory?.name ?? 'Uncategorized',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          formatMinorUnits(topSpending.amountMinor),
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
                        semanticsLabel:
                            '${topCategory?.name ?? 'Uncategorized'} spending',
                      ),
                    ),
                  ],
                ),
              ),
              if (moreCount > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'and $moreCount more ${moreCount == 1 ? 'category' : 'categories'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.mutedText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Aggregate summary of recent transactions — a count for this period plus a
/// one-line preview of the single most recent one, not the per-transaction
/// list (that's the Transactions tab's job) — tapping through to it.
class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({
    required this.transactionCount,
    required this.latest,
    required this.accountNames,
    required this.categoriesById,
    required this.onTap,
  });

  final int transactionCount;
  final TransactionRow? latest;
  final Map<String, String> accountNames;
  final Map<String, CategoryRow> categoriesById;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final latest = this.latest;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent activity', style: theme.textTheme.labelLarge),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (latest == null)
                Text(
                  'No transactions yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.mutedText,
                  ),
                )
              else ...[
                Text(
                  '$transactionCount ${transactionCount == 1 ? 'transaction' : 'transactions'} this month',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.mutedText,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        categoriesById[latest.categoryId]?.name ??
                            (latest.description.isEmpty
                                ? 'Transaction'
                                : latest.description),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      formatMinorUnits(latest.amountMinor),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
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
