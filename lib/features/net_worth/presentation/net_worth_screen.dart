import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/net_worth_data.dart';

/// Net Worth screen (docs/ROADMAP.md §9.1): assets minus liabilities,
/// derived at read time from accounts and loans. Reached from
/// Settings → Insights, alongside Reports — a new screen, not a change to
/// the Dashboard.
class NetWorthScreen extends ConsumerWidget {
  const NetWorthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netWorth = ref.watch(netWorthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Net Worth')),
      body: netWorth.when(
        data: (data) => data.assets.isEmpty && data.liabilities.isEmpty
            ? const EmptyState(
                icon: Icons.balance,
                title: 'Nothing to show yet',
                message: 'Add accounts or loans to see your net worth.',
              )
            : _NetWorthBody(data: data),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(netWorthProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xxxl),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}

class _NetWorthBody extends StatelessWidget {
  const _NetWorthBody({required this.data});

  final NetWorthData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net Worth', style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  formatMinorUnits(data.netWorthMinor),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: data.netWorthMinor >= 0
                        ? colors.income
                        : colors.expense,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Assets',
          totalMinor: data.assetsMinor,
          entries: data.assets,
          amountColor: colors.income,
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Liabilities',
          totalMinor: data.liabilitiesMinor,
          entries: data.liabilities,
          amountColor: colors.expense,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.totalMinor,
    required this.entries,
    required this.amountColor,
  });

  final String title;
  final int totalMinor;
  final List<NetWorthEntry> entries;
  final Color amountColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.mutedText,
              ),
            ),
            Text(
              formatMinorUnits(totalMinor),
              style: theme.textTheme.labelLarge?.copyWith(color: amountColor),
            ),
          ],
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'None',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.mutedText,
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final entry in entries)
                  ListTile(
                    title: Text(entry.label),
                    trailing: Text(
                      formatMinorUnits(entry.amountMinor),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: amountColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
