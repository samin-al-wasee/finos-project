import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/investment_instrument_type.dart';
import '../domain/investment_progress.dart';
import 'investment_details_screen.dart';
import 'investment_form_screen.dart';
import 'investment_labels.dart';

/// Investments screen (docs/adr/009-investment-accounting.md).
///
/// Reached from Settings, alongside Templates and Recurring Transactions —
/// this is a full CRUD feature like those, not a read-only aggregate like
/// Net Worth or Reports, so it does not live in that "Insights" section
/// (and doesn't get its own bottom-nav tab, which is already full).
///
/// Groups active investments above archived ones. No card view yet — that
/// was an additive polish pass Accounts/Loans/Budgets got only after
/// shipping, not something this feature needs on first release.
class InvestmentsListScreen extends ConsumerWidget {
  const InvestmentsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(investmentProgressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Investments')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-investments',
        onPressed: () => _openForm(context),
        tooltip: 'Add investment',
        child: const Icon(Icons.add),
      ),
      body: progress.when(
        data: (rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.savings_outlined,
                title: 'No investments yet',
                message:
                    'Track fixed-term deposits like FDR, DPS, or '
                    'Sanchayapatra, and their contributions and payouts.',
                action: FilledButton.icon(
                  onPressed: () => _openForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add investment'),
                ),
              )
            : _InvestmentList(rows: rows),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(investmentProgressProvider),
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
      MaterialPageRoute<void>(builder: (_) => const InvestmentFormScreen()),
    );
  }
}

class _InvestmentList extends StatelessWidget {
  const _InvestmentList({required this.rows});

  final List<InvestmentProgress> rows;

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
              'No active investments',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          for (final row in active) _InvestmentTile(progress: row),
        if (archived.isNotEmpty) ...[
          const _SectionHeader(title: 'Archived'),
          for (final row in archived) _InvestmentTile(progress: row),
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

class _InvestmentTile extends StatelessWidget {
  const _InvestmentTile({required this.progress});

  final InvestmentProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final investment = progress.investment;
    final symbol = currencySymbol(investment.currency);

    final tile = ListTile(
      leading: const CircleAvatar(child: Icon(Icons.savings_outlined)),
      title: Text(investment.name),
      subtitle: Text(
        '${investmentInstrumentTypeLabel(investment.instrumentType)} · '
        '${investmentStandingLabel(progress)} · '
        'Matures ${formatDate(investment.maturityDate)}',
      ),
      trailing: Text(
        formatMinorUnits(progress.contributedMinor, symbol: symbol),
        style: theme.textTheme.titleSmall?.copyWith(
          color: progress.isArchived ? colors.mutedText : null,
        ),
      ),
      // Deliberately still tappable when archived (unlike disabling via
      // ListTile.enabled, which would also block the tap) — restoring an
      // archived investment happens from its own details screen, the same
      // precedent `loans_list_screen.dart`'s archived tiles follow.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InvestmentDetailsScreen(investmentId: investment.id),
        ),
      ),
    );

    return progress.isArchived ? Opacity(opacity: 0.6, child: tile) : tile;
  }
}
