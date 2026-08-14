import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/savings_goal_progress.dart';
import 'savings_goal_contribution_dialog.dart';
import 'savings_goal_form_screen.dart';
import 'savings_goal_labels.dart';
import 'savings_goal_withdrawal_dialog.dart';

/// Savings goal detail screen (docs/adr/011-savings-goals.md).
///
/// Shows the target, what has been saved, and progress toward it, then the
/// individual contributions and withdrawals. Recording either happens here
/// rather than in the transaction form, so a withdrawal can be checked
/// against what is currently saved.
class SavingsGoalDetailsScreen extends ConsumerWidget {
  const SavingsGoalDetailsScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(savingsGoalProgressByIdProvider(goalId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings Goal'),
        actions: [
          progress.maybeWhen(
            data: (value) => value == null
                ? const SizedBox.shrink()
                : _GoalMenu(progress: value),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: progress.when(
        data: (value) => value == null
            ? const Center(child: Text('This goal no longer exists.'))
            : _Details(progress: value),
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.progress});

  final SavingsGoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final goal = progress.goal;
    final symbol = currencySymbol(goal.currency);
    final movements = ref.watch(savingsGoalMovementsProvider(goal.id));

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(goal.name, style: theme.textTheme.headlineSmall),
        ),

        // ── Figures ───────────────────────────────────────────────────────
        _AmountRow(
          label: 'Target',
          value: formatMinorUnits(goal.targetAmountMinor, symbol: symbol),
        ),
        _AmountRow(
          label: 'Saved',
          value: formatMinorUnits(progress.currentAmountMinor, symbol: symbol),
          emphasise: true,
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: progress.progressFraction,
              minHeight: AppSpacing.sm,
              backgroundColor: colors.border,
              color: progress.isAchieved ? colors.success : colors.transfer,
              semanticsLabel: '${goal.name} progress',
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // The standing is stated in words, never colour alone
              // (AGENTS.md §21).
              Text(
                savingsGoalStandingLabel(progress),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: progress.isOverdue()
                      ? colors.error
                      : progress.isAchieved
                      ? colors.success
                      : colors.mutedText,
                ),
              ),
              if (goal.deadlineDate != null)
                Text(
                  'By ${formatDate(goal.deadlineDate!)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.mutedText,
                  ),
                ),
            ],
          ),
        ),

        if (goal.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Text(goal.description, style: theme.textTheme.bodyMedium),
          ),

        // ── Contribute / Withdraw ────────────────────────────────────────
        if (!progress.isArchived)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _contribute(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Contribute'),
                  ),
                ),
                if (progress.currentAmountMinor > 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _withdraw(context, ref),
                      icon: const Icon(Icons.remove),
                      label: const Text('Withdraw'),
                    ),
                  ),
                ],
              ],
            ),
          ),

        // ── History ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            'Activity',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.mutedText,
            ),
          ),
        ),
        movements.when(
          data: (rows) => rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Text(
                    'No contributions or withdrawals recorded yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final row in rows)
                      ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(
                          row.description.isEmpty
                              ? 'Movement'
                              : row.description,
                        ),
                        subtitle: Text(formatDate(row.date)),
                        trailing: Text(
                          formatMinorUnits(row.amountMinor, symbol: symbol),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                  ],
                ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(error.toString()),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }

  Future<void> _contribute(BuildContext context, WidgetRef ref) async {
    final result = await SavingsGoalContributionDialog.show(
      context,
      progress: progress,
    );
    if (result == null || !context.mounted) return;

    try {
      await ref
          .read(savingsGoalControllerProvider)
          .contribute(
            goalId: progress.goal.id,
            amountMinor: result.amountMinor,
            date: result.date,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Contribution recorded')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not record it: $e')));
      }
    }
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final result = await SavingsGoalWithdrawalDialog.show(
      context,
      progress: progress,
    );
    if (result == null || !context.mounted) return;

    try {
      await ref
          .read(savingsGoalControllerProvider)
          .withdraw(
            goalId: progress.goal.id,
            amountMinor: result.amountMinor,
            date: result.date,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Withdrawal recorded')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not record it: $e')));
      }
    }
  }
}

/// A labelled figure on the details screen.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          Text(
            value,
            style: emphasise
                ? theme.textTheme.titleLarge
                : theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

/// Edit, archive/restore, and delete for a savings goal.
class _GoalMenu extends ConsumerWidget {
  const _GoalMenu({required this.progress});

  final SavingsGoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Goal options',
      onSelected: (value) => _handle(context, ref, value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (progress.isArchived)
          const PopupMenuItem(value: 'restore', child: Text('Restore'))
        else
          const PopupMenuItem(value: 'archive', child: Text('Archive')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final controller = ref.read(savingsGoalControllerProvider);

    if (value == 'edit') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SavingsGoalFormScreen(initial: progress.goal),
        ),
      );
      return;
    }

    if (value == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this goal?'),
          content: const Text(
            'This removes the goal. Goals with contributions or withdrawals '
            'recorded cannot be deleted — archive them instead.',
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
      if (confirmed != true || !context.mounted) return;
      try {
        await controller.delete(progress.goal.id);
        if (context.mounted) Navigator.of(context).pop();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
      return;
    }

    try {
      switch (value) {
        case 'archive':
          await controller.archive(progress.goal.id);
        case 'restore':
          await controller.restore(progress.goal.id);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }
}
