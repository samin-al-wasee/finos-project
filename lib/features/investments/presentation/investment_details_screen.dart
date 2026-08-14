import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../recurring/domain/due_occurrences.dart';
import '../application/investment_controller.dart';
import '../domain/investment_contribution_mode.dart';
import '../domain/investment_instrument_type.dart';
import '../domain/investment_progress.dart';
import 'investment_form_screen.dart';
import 'investment_labels.dart';
import 'investment_payout_dialog.dart';

/// Investment detail screen (docs/adr/009-investment-accounting.md).
///
/// Shows what has been contributed and paid out, then surfaces any due
/// contribution or payout for the user to confirm or skip — never created
/// automatically (docs/ARCHITECTURE.md §20) — followed by the movement
/// history.
class InvestmentDetailsScreen extends ConsumerWidget {
  const InvestmentDetailsScreen({super.key, required this.investmentId});

  final String investmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(investmentProgressByIdProvider(investmentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Investment'),
        actions: [
          progress.maybeWhen(
            data: (value) => value == null
                ? const SizedBox.shrink()
                : _InvestmentMenu(progress: value),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: progress.when(
        data: (value) => value == null
            ? const Center(child: Text('This investment no longer exists.'))
            : _Details(progress: value),
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.progress});

  final InvestmentProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final investment = progress.investment;
    final symbol = currencySymbol(investment.currency);
    final movements = ref.watch(investmentMovementsProvider(investment.id));

    final dueContributions = progress.dueContributions();
    final duePayouts = progress.duePayouts();
    final maturityPayoutDue = progress.isMaturityPayoutDue();

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(investment.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${investmentInstrumentTypeLabel(investment.instrumentType)} · '
                '${investmentContributionModeLabel(investment.contributionMode)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.mutedText,
                ),
              ),
            ],
          ),
        ),

        // ── Figures ───────────────────────────────────────────────────────
        _AmountRow(
          label: 'Contributed',
          value: formatMinorUnits(progress.contributedMinor, symbol: symbol),
        ),
        _AmountRow(
          label: 'Paid out',
          value: formatMinorUnits(progress.payoutReceivedMinor, symbol: symbol),
        ),

        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // The standing is stated in words, never colour alone
              // (AGENTS.md §21).
              Text(
                investmentStandingLabel(progress),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: progress.isSettled
                      ? colors.success
                      : maturityPayoutDue
                      ? colors.warning
                      : colors.mutedText,
                ),
              ),
              Text(
                'Matures ${formatDate(investment.maturityDate)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.mutedText,
                ),
              ),
            ],
          ),
        ),

        // ── Due contribution ─────────────────────────────────────────────
        if (dueContributions != null && dueContributions.dates.isNotEmpty)
          _DueContributionCard(progress: progress, due: dueContributions),

        // ── Due payout / maturity payout ─────────────────────────────────
        if (maturityPayoutDue)
          _DuePayoutCard(progress: progress, isMaturityPayout: true)
        else if (duePayouts != null && duePayouts.dates.isNotEmpty)
          _DuePayoutCard(progress: progress, isMaturityPayout: false),

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
                    'No contributions or payouts recorded yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final row in rows)
                      ListTile(
                        leading: const Icon(Icons.savings_outlined),
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
}

/// A labelled figure on the details screen.
class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.value});

  final String label;
  final String value;

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
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// Surfaces a due DPS installment for the user to confirm or skip. The
/// amount is fixed, so unlike a payout there is nothing to collect first.
class _DueContributionCard extends ConsumerWidget {
  const _DueContributionCard({required this.progress, required this.due});

  final InvestmentProgress progress;
  final DueOccurrences due;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final symbol = currencySymbol(progress.investment.currency);
    final count = due.dates.length;
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
            Text(
              count == 1 ? 'Installment due' : '$count installments due',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${formatMinorUnits(progress.investment.amountMinor, symbol: symbol)} '
              'since $oldest',
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _skip(context, ref),
                  child: const Text('Skip'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: () => _confirm(context, ref),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) => _run(
    context,
    ref,
    (c) => c.confirmNextContribution(progress.investment.id),
  );

  Future<void> _skip(BuildContext context, WidgetRef ref) =>
      _run(context, ref, (c) => c.skipNextContribution(progress.investment.id));

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(InvestmentController) action,
  ) async {
    try {
      await action(ref.read(investmentControllerProvider));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }
}

/// Surfaces a due periodic profit payout, or the final maturity payout, for
/// the user to confirm (with an entered amount) or skip.
class _DuePayoutCard extends ConsumerWidget {
  const _DuePayoutCard({
    required this.progress,
    required this.isMaturityPayout,
  });

  final InvestmentProgress progress;
  final bool isMaturityPayout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

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
            Text(
              isMaturityPayout ? 'Maturity payout due' : 'Profit payout due',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isMaturityPayout
                  ? 'This investment has matured. Confirm the amount you '
                        'actually received.'
                  : 'Confirm the profit amount you actually received, or '
                        'skip if it has not arrived yet.',
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isMaturityPayout)
                  OutlinedButton(
                    onPressed: () => _skip(context, ref),
                    child: const Text('Skip'),
                  ),
                if (!isMaturityPayout) const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: () => _confirm(context, ref),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final result = await InvestmentPayoutDialog.show(
      context,
      progress: progress,
      isMaturityPayout: isMaturityPayout,
    );
    if (result == null || !context.mounted) return;

    try {
      await ref
          .read(investmentControllerProvider)
          .confirmNextPayout(
            progress.investment.id,
            amountMinor: result.amountMinor,
            date: result.date,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Payout recorded')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not record it: $e')));
      }
    }
  }

  Future<void> _skip(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(investmentControllerProvider)
          .skipNextPayout(progress.investment.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }
}

/// Edit, archive/restore, and delete for an investment.
class _InvestmentMenu extends ConsumerWidget {
  const _InvestmentMenu({required this.progress});

  final InvestmentProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Investment options',
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
    final controller = ref.read(investmentControllerProvider);

    if (value == 'edit') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InvestmentFormScreen(initial: progress.investment),
        ),
      );
      return;
    }

    if (value == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this investment?'),
          content: const Text(
            'This removes the investment and, for a lump-sum instrument, the '
            'contribution that created it. Investments with a payout — or a '
            'recurring instrument with any confirmed installment — cannot be '
            'deleted; archive them instead.',
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
        await controller.delete(progress.investment.id);
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
          await controller.archive(progress.investment.id);
        case 'restore':
          await controller.restore(progress.investment.id);
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
