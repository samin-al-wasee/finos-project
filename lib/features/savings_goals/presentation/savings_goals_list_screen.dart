import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/savings_goal_progress.dart';
import 'savings_goal_details_screen.dart';
import 'savings_goal_form_screen.dart';
import 'savings_goal_labels.dart';

/// Savings Goals screen (docs/adr/011-savings-goals.md).
///
/// Reached from Settings, alongside Templates, Recurring Transactions, and
/// Investments — a full CRUD feature like those, not a read-only aggregate
/// like Net Worth or Reports.
///
/// Groups active goals above archived ones. No card view, Dashboard
/// summary, or Reports integration yet — those were additive polish passes
/// other features got only after shipping, not something this feature needs
/// on first release.
class SavingsGoalsListScreen extends ConsumerWidget {
  const SavingsGoalsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(savingsGoalProgressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-savings-goals',
        onPressed: () => _openForm(context),
        tooltip: 'Add goal',
        child: const Icon(Icons.add),
      ),
      body: progress.when(
        data: (rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.flag_outlined,
                title: 'No savings goals yet',
                message:
                    'Set a target for an emergency fund, a big purchase, '
                    'or anything else you\'re saving toward.',
                action: FilledButton.icon(
                  onPressed: () => _openForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add goal'),
                ),
              )
            : _GoalList(rows: rows),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(savingsGoalProgressProvider),
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

  void _openForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SavingsGoalFormScreen()),
    );
  }
}

class _GoalList extends StatelessWidget {
  const _GoalList({required this.rows});

  final List<SavingsGoalProgress> rows;

  @override
  Widget build(BuildContext context) {
    final active = rows.where((r) => !r.isArchived).toList();
    final archived = rows.where((r) => r.isArchived).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              'No active goals',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          for (final row in active) _GoalTile(progress: row),
        if (archived.isNotEmpty) ...[
          const _SectionHeader(title: 'Archived'),
          for (final row in archived) _GoalTile(progress: row),
        ],
      ],
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

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.progress});

  final SavingsGoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final goal = progress.goal;
    final symbol = currencySymbol(goal.currency);

    final subtitleParts = [
      savingsGoalStandingLabel(progress),
      if (goal.deadlineDate != null) 'By ${formatDate(goal.deadlineDate!)}',
    ];

    final tile = ListTile(
      leading: const CircleAvatar(child: Icon(Icons.flag_outlined)),
      title: Text(goal.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subtitleParts.join(' · ')),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: progress.progressFraction,
              minHeight: AppSpacing.xs,
              backgroundColor: colors.border,
              color: progress.isAchieved ? colors.success : colors.transfer,
              semanticsLabel: '${goal.name} progress',
            ),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Text(
        formatMinorUnits(progress.currentAmountMinor, symbol: symbol),
        style: theme.textTheme.titleSmall?.copyWith(
          color: progress.isArchived ? colors.mutedText : null,
        ),
      ),
      // Deliberately still tappable when archived — restoring an archived
      // goal happens from its own details screen, the same precedent
      // `investments_list_screen.dart`'s archived tiles follow.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SavingsGoalDetailsScreen(goalId: goal.id),
        ),
      ),
    );

    return progress.isArchived ? Opacity(opacity: 0.6, child: tile) : tile;
  }
}
