import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../accounts/domain/account_status.dart';
import '../../accounts/presentation/account_details_screen.dart';
import '../../accounts/presentation/account_form_screen.dart';
import '../../accounts/presentation/account_type_label.dart';
import '../../transactions/presentation/transaction_form_screen.dart';
import '../../transactions/presentation/transaction_tile.dart';
import '../domain/dashboard_data.dart';

/// Home tab content (FR-07).
///
/// Shows the financial overview: total balance, this-month income and expenses,
/// per-account balances, and the five most recent transactions. Recomputes
/// automatically whenever accounts or transactions change.
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
      appBar: AppBar(title: const Text('FinOS')),
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
        const SizedBox(height: AppSpacing.lg),
        const _SectionHeader(title: 'Accounts'),
        for (final accountBalance in data.accountBalances)
          _AccountBalanceTile(accountBalance: accountBalance),
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
