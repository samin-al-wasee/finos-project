import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/loan_direction.dart';
import '../domain/loan_progress.dart';
import 'loan_details_screen.dart';
import 'loan_form_screen.dart';
import 'loan_labels.dart';

/// Loans tab (FR-06, docs/UI_DESIGN.md §21).
///
/// Splits loans into "I Owe" and "Owed to Me" rather than showing one mixed list,
/// because that is the distinction users actually reason about and mixing the two
/// invites exactly the ambiguity AGENTS.md §10 warns against.
class LoansListScreen extends ConsumerWidget {
  const LoansListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loanProgressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-loans',
        onPressed: () => openLoanForm(context),
        tooltip: 'Add loan',
        child: const Icon(Icons.add),
      ),
      body: loans.when(
        data: (rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.handshake_outlined,
                title: 'No loans yet',
                message:
                    'Track money you have lent out and money you owe, and '
                    'record repayments as they happen.',
                action: FilledButton.icon(
                  onPressed: () => openLoanForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add loan'),
                ),
              )
            : _LoanList(rows: rows),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(loansStreamProvider),
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

/// Opens the add/edit loan form.
void openLoanForm(BuildContext context, {LoanProgress? initial}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LoanFormScreen(initial: initial?.loan),
    ),
  );
}

/// Groups loans by direction, with archived ones collected below.
class _LoanList extends StatelessWidget {
  const _LoanList({required this.rows});

  final List<LoanProgress> rows;

  @override
  Widget build(BuildContext context) {
    final active = rows.where((r) => !r.isArchived).toList();
    final archived = rows.where((r) => r.isArchived).toList();

    final children = <Widget>[
      // "I Owe" first: a liability is the more urgent of the two.
      for (final direction in [LoanDirection.borrowed, LoanDirection.lent])
        if (active.any((r) => r.direction == direction)) ...[
          _SectionHeader(
            title: loanDirectionHeading(direction),
            totalMinor: active
                .where((r) => r.direction == direction)
                .fold<int>(0, (sum, r) => sum + r.outstandingMinor),
          ),
          for (final row in active.where((r) => r.direction == direction))
            _LoanTile(progress: row),
        ],
      if (archived.isNotEmpty) ...[
        const _SectionHeader(title: 'Archived'),
        for (final row in archived) _LoanTile(progress: row, archived: true),
      ],
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: children,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.totalMinor});

  final String title;

  /// Combined outstanding amount for the section, when it has one.
  final int? totalMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.mutedText,
            ),
          ),
          if (totalMinor != null)
            Text(
              '${formatMinorUnits(totalMinor!)} remaining',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.mutedText,
              ),
            ),
        ],
      ),
    );
  }
}

/// One loan: who it is with, what is left, and how far along it is.
class _LoanTile extends StatelessWidget {
  const _LoanTile({required this.progress, this.archived = false});

  final LoanProgress progress;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final symbol = currencySymbol(progress.loan.currency);
    final standing = progress.standing();

    final tile = ListTile(
      leading: CircleAvatar(
        child: Icon(
          progress.direction == LoanDirection.borrowed
              ? Icons.south_west
              : Icons.north_east,
        ),
      ),
      title: Text(progress.loan.name),
      subtitle: Text(
        // Amounts and words carry the meaning; colour only reinforces it.
        '${formatMinorUnits(progress.outstandingMinor, symbol: symbol)} '
        'remaining of '
        '${formatMinorUnits(progress.principalMinor, symbol: symbol)}'
        ' · ${loanStandingLabel(standing)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: standing == LoanStanding.overdue
              ? colors.error
              : colors.mutedText,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoanDetailsScreen(loanId: progress.loan.id),
        ),
      ),
    );

    return archived ? Opacity(opacity: 0.6, child: tile) : tile;
  }
}
