import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_indicator.dart';
import '../../transactions/domain/transaction_type.dart';
import '../../transactions/presentation/transaction_tile.dart';
import '../domain/budget_progress.dart';
import '../domain/budget_scope.dart';
import 'budget_bar.dart';
import 'budget_details_screen.dart';
import 'budget_labels.dart';

/// Card view for the Budgets tab (alongside, not replacing, the plain list):
/// one budget per page in a swipeable [PageView], with a live feed of that
/// budget's matching spending below it.
///
/// [rows] is passed in already ordered by [rows]' own natural order — the
/// caller orders active budgets the same way the list view groups them
/// (by period) before handing them here.
class BudgetCardView extends ConsumerStatefulWidget {
  const BudgetCardView({super.key, required this.rows});

  final List<BudgetProgress> rows;

  @override
  ConsumerState<BudgetCardView> createState() => _BudgetCardViewState();
}

class _BudgetCardViewState extends ConsumerState<BudgetCardView> {
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
    final rows = widget.rows;
    // Guards against the currently-viewed budget dropping out of the active
    // list (e.g. archived elsewhere) while this screen is open.
    final selectedIndex = _selectedIndex.clamp(0, rows.length - 1);

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _pageController,
            itemCount: rows.length,
            onPageChanged: (index) => setState(() => _selectedIndex = index),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: _BudgetCard(progress: rows[index]),
              );
            },
          ),
        ),
        if (rows.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          PageIndicator(count: rows.length, selectedIndex: selectedIndex),
        ],
        const SizedBox(height: AppSpacing.sm),
        Expanded(child: _BudgetFeed(progress: rows[selectedIndex])),
      ],
    );
  }
}

/// One budget rendered as a bigger card, mirroring the list's own
/// `_BudgetCard` content. Tapping it opens the existing
/// [BudgetDetailsScreen] — card view is an additional way to browse, not a
/// replacement for it (edit/archive/delete stay on the list's own menu).
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final symbol = currencySymbol(progress.budget.currency);
    final spent = formatMinorUnits(progress.spentMinor, symbol: symbol);
    final limit = formatMinorUnits(progress.limitMinor, symbol: symbol);
    final carryIn = budgetCarryInLabel(progress);

    return Card(
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BudgetDetailsScreen(budgetId: progress.budget.id),
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
                  Icon(budgetScopeIcon(progress), color: colors.mutedText),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          budgetScopeLabel(progress),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          budgetWindowLabel(progress.window),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Text('$spent / $limit', style: theme.textTheme.headlineSmall),
              if (carryIn != null)
                Text(
                  carryIn,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.mutedText,
                  ),
                ),
              BudgetBar(progress: progress),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    budgetHealthLabel(progress.health),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: healthColor(colors, progress.health),
                    ),
                  ),
                  Text(
                    progress.isExceeded
                        ? '${formatMinorUnits(-progress.remainingMinor, symbol: symbol)} over'
                        : '${formatMinorUnits(progress.remainingMinor, symbol: symbol)} left',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live spending feed for one budget: every expense inside its current
/// window that matches its scope, reusing the [budgetScopeMatches] predicate
/// (no new DAO query — filters the already-loaded transactions stream, same
/// approach as the Accounts card view's feed).
class _BudgetFeed extends ConsumerWidget {
  const _BudgetFeed({required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(transactionsStreamProvider);
    final accounts = ref.watch(accountsStreamProvider);
    final categories = ref.watch(categoriesStreamProvider);

    return transactions.when(
      data: (rows) => accounts.when(
        data: (accountRows) => categories.when(
          data: (categoryRows) => _buildFeed(
            rows: rows,
            accounts: accountRows,
            categories: categoryRows,
          ),
          error: (e, _) => _ErrorState(message: e.toString()),
          loading: () => const _LoadingState(),
        ),
        error: (e, _) => _ErrorState(message: e.toString()),
        loading: () => const _LoadingState(),
      ),
      error: (e, _) => _ErrorState(message: e.toString()),
      loading: () => const _LoadingState(),
    );
  }

  Widget _buildFeed({
    required List<TransactionRow> rows,
    required List<FinancialAccountRow> accounts,
    required List<CategoryRow> categories,
  }) {
    final accountNames = {for (final a in accounts) a.id: a.name};
    final categoriesById = {for (final c in categories) c.id: c};

    final matched =
        rows
            .where(
              (row) =>
                  row.type == TransactionType.expense &&
                  progress.window.contains(row.date) &&
                  budgetScopeMatches(progress.scope, row),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    if (matched.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No spending recorded for this period yet',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: matched.length,
      itemBuilder: (context, index) {
        final row = matched[index];
        final category = row.categoryId == null
            ? null
            : categoriesById[row.categoryId];
        return TransactionTile(
          key: ValueKey(row.id),
          transaction: row,
          accountName: accountNames[row.accountId] ?? row.accountId,
          categoryName: category?.name,
          categoryIconKey: category?.icon,
        );
      },
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxxl),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      message: message,
    );
  }
}
