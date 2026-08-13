import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/budget_period.dart';
import '../domain/budget_progress.dart';
import '../domain/budget_status.dart';
import 'budget_bar.dart';
import 'budget_details_screen.dart';
import 'budget_form_screen.dart';
import 'budget_labels.dart';

/// Budget overview screen (FR-04, docs/UI_DESIGN.md §19–§20).
///
/// Answers "how much can I still spend?": each budget shows spending against its
/// limit, a progress bar, and what is left. Active budgets are grouped by period
/// with archived ones collected below. A floating action button opens the create
/// form; per-card menus expose edit/archive/restore/delete.
class BudgetsListScreen extends ConsumerWidget {
  const BudgetsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetProgressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton(
        // Distinct from the other tab FABs — see the note in
        // transactions_list_screen.dart.
        heroTag: 'fab-budgets',
        onPressed: () => openBudgetForm(context),
        tooltip: 'Add budget',
        child: const Icon(Icons.add),
      ),
      body: budgets.when(
        data: (rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.pie_chart_outline,
                title: 'No budgets yet',
                message:
                    'Set a spending limit for a category to see how much is '
                    'left to spend.',
                action: FilledButton.icon(
                  onPressed: () => openBudgetForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add budget'),
                ),
              )
            : _BudgetList(rows: rows),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(budgetsStreamProvider),
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

/// Opens the add/edit budget form.
void openBudgetForm(BuildContext context, {BudgetProgress? initial}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BudgetFormScreen(initial: initial?.budget),
    ),
  );
}

/// Groups [rows] into one section per period, with archived budgets last.
class _BudgetList extends StatelessWidget {
  const _BudgetList({required this.rows});

  final List<BudgetProgress> rows;

  @override
  Widget build(BuildContext context) {
    final active = rows
        .where((r) => r.budget.status == BudgetStatus.active)
        .toList();
    final archived = rows
        .where((r) => r.budget.status == BudgetStatus.archived)
        .toList();

    final children = <Widget>[
      for (final period in BudgetPeriod.values)
        if (active.any((r) => r.budget.period == period)) ...[
          _SectionHeader(title: budgetPeriodLabel(period)),
          for (final row in active.where((r) => r.budget.period == period))
            _BudgetCard(progress: row),
        ],
      if (archived.isNotEmpty) ...[
        const _SectionHeader(title: 'Archived'),
        for (final row in archived) _BudgetCard(progress: row, archived: true),
      ],
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: children,
    );
  }
}

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

/// One budget: category, window, spent-of-limit, progress bar, and what's
/// left. Tapping the card opens its history (docs/ROADMAP.md §8.3); the menu
/// stays a separate control for edit/archive/delete.
class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.progress, this.archived = false});

  final BudgetProgress progress;
  final bool archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final symbol = currencySymbol(progress.budget.currency);

    final spent = formatMinorUnits(progress.spentMinor, symbol: symbol);
    final limit = formatMinorUnits(progress.limitMinor, symbol: symbol);
    // Amounts carry the meaning; the health colour only reinforces it
    // (AGENTS.md §21).
    final remaining = progress.isExceeded
        ? '${formatMinorUnits(-progress.remainingMinor, symbol: symbol)} '
              'over budget'
        : '${formatMinorUnits(progress.remainingMinor, symbol: symbol)} '
              'remaining';

    // Everything except the menu button, merged into one screen-reader
    // announcement ("Groceries, this month, ৳500 / ৳800, near limit, ৳300
    // remaining") instead of five disjoint stops (docs/UI_DESIGN.md §43).
    // The menu stays outside the merge so it remains an independently
    // focusable control rather than being absorbed into the label.
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(child: Icon(budgetScopeIcon(progress))),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    budgetScopeLabel(progress),
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    archived ? 'Archived' : budgetWindowLabel(progress.window),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('$spent / $limit', style: theme.textTheme.titleLarge),
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
    );

    final card = Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        BudgetDetailsScreen(budgetId: progress.budget.id),
                  ),
                ),
                child: MergeSemantics(child: info),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => _handleMenu(context, ref, value),
              itemBuilder: (context) => [
                if (!archived)
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (archived)
                  const PopupMenuItem(value: 'restore', child: Text('Restore'))
                else
                  const PopupMenuItem(value: 'archive', child: Text('Archive')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );

    return archived ? Opacity(opacity: 0.6, child: card) : card;
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    if (value == 'edit') {
      openBudgetForm(context, initial: progress);
      return;
    }
    if (value == 'delete') {
      await _confirmDelete(context, ref);
      return;
    }

    final controller = ref.read(budgetControllerProvider);
    try {
      switch (value) {
        case 'archive':
          await controller.archive(progress.budget.id);
        case 'restore':
          await controller.restore(progress.budget.id);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update the budget: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this budget?'),
        content: const Text(
          'This removes the budget and its limit. Your transactions and '
          'balances are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(budgetControllerProvider).delete(progress.budget.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Budget deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }
}
