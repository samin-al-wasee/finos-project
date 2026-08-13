import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_indicator.dart';
import '../domain/loan_direction.dart';
import '../domain/loan_group.dart';
import '../domain/loan_progress.dart';
import 'loan_details_screen.dart';
import 'loan_labels.dart';

/// Card view for the Loans tab (alongside, not replacing, the plain list):
/// one loan relationship per page in a swipeable [PageView], with a live
/// feed of that loan's repayment activity below it.
///
/// [groups] is passed in already ordered borrowed-then-lent by the caller —
/// the same "I Owe" before "Owed to Me" order the list view uses
/// (docs/UI_DESIGN.md §21) — so direction is never mixed, and each card also
/// carries an explicit direction icon and label so the split stays clear
/// even without a separate tab per direction.
class LoanCardView extends ConsumerStatefulWidget {
  const LoanCardView({super.key, required this.groups});

  final List<LoanGroup> groups;

  @override
  ConsumerState<LoanCardView> createState() => _LoanCardViewState();
}

class _LoanCardViewState extends ConsumerState<LoanCardView> {
  late final PageController _pageController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    // Guards against the currently-viewed relationship dropping out of the
    // active list (e.g. archived elsewhere) while this screen is open.
    final selectedIndex = _selectedIndex.clamp(0, groups.length - 1);

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _pageController,
            itemCount: groups.length,
            onPageChanged: (index) => setState(() => _selectedIndex = index),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: _LoanCard(group: groups[index]),
              );
            },
          ),
        ),
        if (groups.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          PageIndicator(count: groups.length, selectedIndex: selectedIndex),
        ],
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: _LoanFeed(loanId: groups[selectedIndex].primary.loan.id),
        ),
      ],
    );
  }
}

/// One loan relationship rendered as a bigger card. Tapping it opens the
/// existing [LoanDetailsScreen] for repayments/extend — card view is an
/// additional way to browse, not a replacement for that screen.
class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.group});

  final LoanGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final primary = group.primary;
    final archived = group.active.isEmpty;
    final symbol = currencySymbol(primary.loan.currency);
    final standing = archived ? primary.standing() : group.standing();
    final outstandingMinor = archived
        ? primary.outstandingMinor
        : group.outstandingMinor;
    final principalMinor = archived
        ? primary.principalMinor
        : group.principalMinor;

    return Card(
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LoanDetailsScreen(loanId: primary.loan.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    group.direction == LoanDirection.borrowed
                        ? Icons.south_west
                        : Icons.north_east,
                    color: colors.mutedText,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      primary.loan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (group.isLinked)
                    Text(
                      '+${group.members.length - 1} linked',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.mutedText,
                      ),
                    ),
                ],
              ),
              Text(
                loanDirectionHeading(group.direction),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedText,
                ),
              ),
              Text(
                formatMinorUnits(outstandingMinor, symbol: symbol),
                style: theme.textTheme.headlineSmall,
              ),
              Text(
                'of ${formatMinorUnits(principalMinor, symbol: symbol)} '
                '· ${loanStandingLabel(standing)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: standing == LoanStanding.overdue
                      ? colors.error
                      : colors.mutedText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live repayment/activity feed for one loan, reusing the already-assembled
/// [loanMovementsProvider] — no new filtering step, unlike the account feed,
/// since that provider already returns just this loan's transactions
/// (`TransactionDao.forLoan`, ADR-004).
class _LoanFeed extends ConsumerWidget {
  const _LoanFeed({required this.loanId});

  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(loanMovementsProvider(loanId));

    return movements.when(
      data: (rows) => rows.isEmpty
          ? const EmptyState(
              icon: Icons.handshake_outlined,
              title: 'No repayments recorded yet',
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: rows.length,
              itemBuilder: (context, index) => _LoanMovementTile(
                key: ValueKey(rows[index].id),
                row: rows[index],
              ),
            ),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        message: e.toString(),
      ),
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxxl),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

/// One repayment/activity row — mirrors the inline tile
/// `loan_details_screen.dart`'s own Activity section already renders.
class _LoanMovementTile extends StatelessWidget {
  const _LoanMovementTile({super.key, required this.row});

  final TransactionRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: const Icon(Icons.handshake_outlined),
      title: Text(row.description.isEmpty ? 'Movement' : row.description),
      subtitle: Text(formatDate(row.date)),
      trailing: Text(
        formatMinorUnits(row.amountMinor),
        style: theme.textTheme.titleSmall,
      ),
    );
  }
}
