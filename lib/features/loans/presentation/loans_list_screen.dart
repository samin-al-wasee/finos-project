import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/loan_direction.dart';
import '../domain/loan_group.dart';
import '../domain/loan_progress.dart';
import 'loan_card_view.dart';
import 'loan_details_screen.dart';
import 'loan_form_screen.dart';
import 'loan_labels.dart';

/// Whether the Loans tab shows every relationship as a plain list, or one at
/// a time as a swipeable card with its own repayment feed below. Card view is
/// additive — list stays the default.
enum _ViewMode { list, card }

/// Loans tab (FR-06, docs/UI_DESIGN.md §21).
///
/// Splits loans into "I Owe" and "Owed to Me" rather than showing one mixed list,
/// because that is the distinction users actually reason about and mixing the two
/// invites exactly the ambiguity AGENTS.md §10 warns against.
///
/// Rows are grouped into relationships (docs/adr/006-loan-relationships.md): a
/// loan that has been extended, or linked to on creation, renders as one tile
/// alongside the loans it is linked with, rather than as separate unrelated
/// entries.
class LoansListScreen extends ConsumerStatefulWidget {
  const LoansListScreen({super.key});

  @override
  ConsumerState<LoansListScreen> createState() => _LoansListScreenState();
}

class _LoansListScreenState extends ConsumerState<LoansListScreen> {
  _ViewMode _viewMode = _ViewMode.list;

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(loanGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans'),
        actions: [
          groups.maybeWhen(
            data: (rows) {
              final hasActive = rows.any((g) => g.active.isNotEmpty);
              if (!hasActive) return const SizedBox.shrink();
              final isCard = _viewMode == _ViewMode.card;
              return IconButton(
                icon: Icon(isCard ? Icons.view_list : Icons.view_carousel),
                tooltip: isCard ? 'List view' : 'Card view',
                onPressed: () => setState(
                  () => _viewMode = isCard ? _ViewMode.list : _ViewMode.card,
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-loans',
        onPressed: () => openLoanForm(context),
        tooltip: 'Add loan',
        child: const Icon(Icons.add),
      ),
      body: groups.when(
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
            : _buildBody(rows),
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

  Widget _buildBody(List<LoanGroup> groups) {
    if (_viewMode == _ViewMode.card) {
      // "I Owe" before "Owed to Me" — the same order the list builds below,
      // so card view never mixes the two directions (docs/UI_DESIGN.md §21).
      final ordered = [
        for (final direction in [LoanDirection.borrowed, LoanDirection.lent])
          for (final group in groups.where(
            (g) => g.active.isNotEmpty && g.direction == direction,
          ))
            group,
      ];
      if (ordered.isNotEmpty) return LoanCardView(groups: ordered);
    }
    return _LoanList(groups: groups);
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

/// Opens the loan form in "extend" mode for [loan]
/// (docs/adr/006-loan-relationships.md).
void openExtendLoanForm(BuildContext context, LoanRow loan) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LoanFormScreen(extending: loan)),
  );
}

/// Groups relationships by direction, with fully-archived ones collected
/// below.
class _LoanList extends StatelessWidget {
  const _LoanList({required this.groups});

  final List<LoanGroup> groups;

  @override
  Widget build(BuildContext context) {
    // A relationship is "active" for section purposes as soon as it has any
    // active member; it only drops to "Archived" once every member is.
    final active = groups.where((g) => g.active.isNotEmpty).toList();
    final archived = groups.where((g) => g.active.isEmpty).toList();

    final children = <Widget>[
      // "I Owe" first: a liability is the more urgent of the two.
      for (final direction in [LoanDirection.borrowed, LoanDirection.lent])
        if (active.any((g) => g.direction == direction)) ...[
          _SectionHeader(
            title: loanDirectionHeading(direction),
            totalMinor: active
                .where((g) => g.direction == direction)
                .fold<int>(0, (sum, g) => sum + g.outstandingMinor),
          ),
          for (final group in active.where((g) => g.direction == direction))
            _LoanGroupTile(group: group),
        ],
      if (archived.isNotEmpty) ...[
        const _SectionHeader(title: 'Archived'),
        for (final group in archived)
          _LoanGroupTile(group: group, archived: true),
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

/// One relationship: the primary member's name, the combined figures across
/// active members, and — when more than one loan is linked — a "+N linked"
/// indicator (docs/adr/006-loan-relationships.md).
///
/// A fully-archived relationship falls back to the primary member's own
/// figures rather than a group aggregate, since there are no active members to
/// combine — the same figure a lone archived loan showed before grouping
/// existed.
class _LoanGroupTile extends StatelessWidget {
  const _LoanGroupTile({required this.group, this.archived = false});

  final LoanGroup group;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final primary = group.primary;
    final symbol = currencySymbol(primary.loan.currency);
    final standing = archived ? primary.standing() : group.standing();
    final outstandingMinor = archived
        ? primary.outstandingMinor
        : group.outstandingMinor;
    final principalMinor = archived
        ? primary.principalMinor
        : group.principalMinor;

    final tile = ListTile(
      leading: CircleAvatar(
        child: Icon(
          group.direction == LoanDirection.borrowed
              ? Icons.south_west
              : Icons.north_east,
        ),
      ),
      title: Text(primary.loan.name),
      subtitle: Text(
        // Amounts and words carry the meaning; colour only reinforces it.
        '${formatMinorUnits(outstandingMinor, symbol: symbol)} '
        'remaining of '
        '${formatMinorUnits(principalMinor, symbol: symbol)}'
        ' · ${loanStandingLabel(standing)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: standing == LoanStanding.overdue
              ? colors.error
              : colors.mutedText,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (group.isLinked)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Text(
                '+${group.members.length - 1} linked',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.mutedText,
                ),
              ),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoanDetailsScreen(loanId: primary.loan.id),
        ),
      ),
    );

    return archived ? Opacity(opacity: 0.6, child: tile) : tile;
  }
}
