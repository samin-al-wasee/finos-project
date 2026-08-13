import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/budget_period.dart';
import '../domain/budget_progress.dart';
import 'budget_bar.dart';
import 'budget_labels.dart';

/// A budget's current status plus its history of past periods
/// (docs/ROADMAP.md §8.3).
///
/// History reuses [BudgetProgress] for past windows exactly as the live card
/// does for the current one — same shape, same derived health/remaining
/// getters, so nothing about "what counts as spending" changes for a past
/// period versus today's.
class BudgetDetailsScreen extends ConsumerWidget {
  const BudgetDetailsScreen({super.key, required this.budgetId});

  final String budgetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(budgetProgressProvider);
    final history = ref.watch(budgetHistoryProvider(budgetId));

    return Scaffold(
      appBar: AppBar(title: const Text('Budget history')),
      body: current.when(
        data: (rows) {
          BudgetProgress? found;
          for (final row in rows) {
            if (row.budget.id == budgetId) {
              found = row;
              break;
            }
          }
          if (found == null) {
            return const EmptyState(
              icon: Icons.error_outline,
              title: 'Budget not found',
              message: 'This budget may have been deleted.',
            );
          }
          return _DetailsBody(current: found, history: history);
        },
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(budgetProgressProvider),
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

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.current, required this.history});

  final BudgetProgress current;
  final AsyncValue<List<BudgetProgress>> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final symbol = currencySymbol(current.budget.currency);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            CircleAvatar(child: Icon(budgetScopeIcon(current))),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    budgetScopeLabel(current),
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    budgetPeriodLabel(current.budget.period),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (current.categories.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final category in current.categories)
                Chip(label: Text(category.name)),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _PeriodTile(progress: current, symbol: symbol, isCurrent: true),
        const SizedBox(height: AppSpacing.xl),
        Text('History', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        history.when(
          data: (entries) => entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(
                    current.budget.period == BudgetPeriod.custom
                        ? 'A one-time budget has no repeating history.'
                        : 'No earlier periods yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final entry in entries) ...[
                      _PeriodTile(progress: entry, symbol: symbol),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              "Couldn't load history: $error",
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
            ),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }
}

/// One period's spend-vs-limit — the live card's content, minus the leading
/// icon/name (already shown once, in the screen header) and the edit menu.
class _PeriodTile extends StatelessWidget {
  const _PeriodTile({
    required this.progress,
    required this.symbol,
    this.isCurrent = false,
  });

  final BudgetProgress progress;
  final String symbol;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    final spent = formatMinorUnits(progress.spentMinor, symbol: symbol);
    final limit = formatMinorUnits(progress.limitMinor, symbol: symbol);
    // Amounts carry the meaning; the health colour only reinforces it
    // (AGENTS.md §21).
    final remaining = progress.isExceeded
        ? '${formatMinorUnits(-progress.remainingMinor, symbol: symbol)} '
              'over budget'
        : '${formatMinorUnits(progress.remainingMinor, symbol: symbol)} '
              'remaining';

    return MergeSemantics(
      child: Card(
        color: isCurrent ? theme.colorScheme.surfaceContainerHigh : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                budgetWindowLabel(progress.window),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.mutedText,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('$spent / $limit', style: theme.textTheme.titleLarge),
              if (budgetCarryInLabel(progress) != null)
                Text(
                  budgetCarryInLabel(progress)!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.mutedText,
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              BudgetBar(progress: progress),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    budgetHealthLabel(progress.health),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: healthColor(colors, progress.health),
                    ),
                  ),
                  Text(remaining, style: theme.textTheme.bodyMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
