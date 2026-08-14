import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../transactions/domain/transaction_type.dart';
import '../application/recurring_transaction_controller.dart';
import '../domain/due_recurring_group.dart';
import '../domain/recurrence_frequency.dart';
import '../domain/recurring_status.dart';
import 'recurring_transaction_form_screen.dart';

/// Recurring transaction rules and their due occurrences (docs/ROADMAP.md §8.1).
///
/// A rule never creates a transaction on its own — the "Due" section at the
/// top surfaces what is currently due and lets the user confirm or skip it.
/// The "Active"/"Archived" sections below manage the rules themselves: tapping
/// a rule opens its edit form, with the per-row menu kept for archive/restore/
/// delete, the same split used for budgets and templates elsewhere in the app.
class RecurringTransactionsListScreen extends ConsumerWidget {
  const RecurringTransactionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringTransactionsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring transactions')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-recurring',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const RecurringTransactionFormScreen(),
          ),
        ),
        tooltip: 'Add recurring transaction',
        child: const Icon(Icons.add),
      ),
      body: rules.when(
        data: (rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.repeat,
                title: 'No recurring transactions yet',
                message:
                    'Set up a rule for a subscription or a regular bill and '
                    "confirm it each time it's due.",
                action: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RecurringTransactionFormScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add recurring transaction'),
                ),
              )
            : _RecurringList(rules: rows),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
          action: OutlinedButton.icon(
            onPressed: () =>
                ref.invalidate(recurringTransactionsStreamProvider),
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

class _RecurringList extends ConsumerWidget {
  const _RecurringList({required this.rules});

  final List<RecurringTransactionRow> rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueRecurringGroupsProvider);
    final active = rules
        .where((r) => r.status == RecurringStatus.active)
        .toList();
    final archived = rules
        .where((r) => r.status == RecurringStatus.archived)
        .toList();

    final children = <Widget>[
      ...due.maybeWhen(
        data: (groups) => groups.isEmpty
            ? const <Widget>[]
            : [
                const _SectionHeader(title: 'Due'),
                for (final group in groups) _DueCard(group: group),
              ],
        orElse: () => const <Widget>[],
      ),
      if (active.isNotEmpty) ...[
        const _SectionHeader(title: 'Active'),
        for (final rule in active) _RuleCard(rule: rule),
      ],
      if (archived.isNotEmpty) ...[
        const _SectionHeader(title: 'Archived'),
        for (final rule in archived) _RuleCard(rule: rule, archived: true),
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

/// One rule's due backlog: what's due and bulk actions to confirm or skip it.
///
/// Occurrences are never edited individually here (V1 simplification) — if an
/// occurrence needs different details, the user skips it and enters a
/// transaction manually instead.
class _DueCard extends ConsumerWidget {
  const _DueCard({required this.group});

  final DueRecurringGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final rule = group.rule;
    final due = group.due;
    final count = due.dates.length;

    final countLabel = due.isCapped
        ? '${due.totalCount} due (showing oldest $count)'
        : count == 1
        ? '1 due'
        : '$count due';
    final oldest = formatDate(due.dates.first);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rule.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$countLabel · oldest $oldest · ${formatMinorUnits(rule.amountMinor)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.mutedText,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                TextButton(
                  onPressed: () => _skipAll(context, ref),
                  child: Text(count == 1 ? 'Skip' : 'Skip all'),
                ),
                if (count > 1)
                  OutlinedButton(
                    onPressed: () => _confirmNext(context, ref),
                    child: const Text('Confirm next'),
                  ),
                FilledButton(
                  onPressed: () => _confirmAll(context, ref),
                  child: Text(count == 1 ? 'Confirm' : 'Confirm all'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmNext(BuildContext context, WidgetRef ref) async {
    await _run(
      context,
      ref,
      (controller) => controller.confirmNext(group.rule.id),
      'confirm',
    );
  }

  Future<void> _confirmAll(BuildContext context, WidgetRef ref) async {
    await _run(
      context,
      ref,
      (controller) => controller.confirmAll(group.rule.id),
      'confirm',
    );
  }

  Future<void> _skipAll(BuildContext context, WidgetRef ref) async {
    await _run(
      context,
      ref,
      (controller) => controller.skipAll(group.rule.id),
      'update',
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(RecurringTransactionController controller) action,
    String verb,
  ) async {
    try {
      await action(ref.read(recurringTransactionControllerProvider));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not $verb: $e')));
      }
    }
  }
}

/// One recurring rule: its schedule, tap to edit, menu to archive/restore/
/// delete.
class _RuleCard extends ConsumerWidget {
  const _RuleCard({required this.rule, this.archived = false});

  final RecurringTransactionRow rule;
  final bool archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    final parts = <String>[
      _typeLabel(rule.type),
      formatMinorUnits(rule.amountMinor),
      recurrenceFrequencyLabel(rule.frequency),
      'Next: ${formatDate(rule.nextOccurrence)}',
    ];

    final card = Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RecurringTransactionFormScreen(initial: rule),
                ),
              ),
              child: MergeSemantics(
                child: ListTile(
                  title: Text(rule.name),
                  subtitle: Text(
                    parts.join(' · '),
                    style: TextStyle(color: colors.mutedText),
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenu(context, ref, value),
            itemBuilder: (context) => [
              if (archived)
                const PopupMenuItem(value: 'restore', child: Text('Restore'))
              else
                const PopupMenuItem(value: 'archive', child: Text('Archive')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );

    return archived ? Opacity(opacity: 0.6, child: card) : card;
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    if (value == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this recurring transaction?'),
          content: const Text(
            'This only removes the rule. Transactions it already created are '
            'not affected.',
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
        await ref.read(recurringTransactionControllerProvider).delete(rule.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recurring transaction deleted')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
        }
      }
      return;
    }

    final controller = ref.read(recurringTransactionControllerProvider);
    try {
      switch (value) {
        case 'archive':
          await controller.archive(rule.id);
        case 'restore':
          await controller.restore(rule.id);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }

  static String _typeLabel(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'Income';
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.transfer:
        return 'Transfer';
      case TransactionType.loanReceipt:
      case TransactionType.loanPayment:
        return 'Loan';
      case TransactionType.investmentContribution:
      case TransactionType.investmentPayout:
        return 'Investment';
    }
  }
}
