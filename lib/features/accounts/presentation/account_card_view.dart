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
import '../../transactions/domain/transaction_filter.dart';
import '../../transactions/presentation/transaction_tile.dart';
import 'account_details_screen.dart';
import 'account_type_label.dart';

/// Card view for the Accounts tab (alongside, not replacing, the plain list):
/// one account per page in a swipeable [PageView], with a live feed of that
/// account's transactions/transfers below it.
///
/// Loan repayments need no special handling here: they are ordinary
/// [TransactionRow]s with `accountId` set (ADR-004), so they already fall out
/// of the same account filter as any other transaction.
class AccountCardView extends ConsumerStatefulWidget {
  const AccountCardView({
    super.key,
    required this.rows,
    required this.balances,
  });

  /// The active accounts to page through, in the same order the list view
  /// shows them.
  final List<FinancialAccountRow> rows;

  /// Live balance (opening + net transaction impact) per account id.
  final Map<String, int> balances;

  @override
  ConsumerState<AccountCardView> createState() => _AccountCardViewState();
}

class _AccountCardViewState extends ConsumerState<AccountCardView> {
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
    // Guards against the currently-viewed account being archived out of the
    // active list (or the list otherwise shrinking) while this screen is open.
    final selectedIndex = _selectedIndex.clamp(0, rows.length - 1);

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _pageController,
            itemCount: rows.length,
            onPageChanged: (index) => setState(() => _selectedIndex = index),
            itemBuilder: (context, index) {
              final row = rows[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: _AccountCard(
                  row: row,
                  balanceMinor:
                      widget.balances[row.id] ?? row.openingBalanceMinor,
                ),
              );
            },
          ),
        ),
        if (rows.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          PageIndicator(count: rows.length, selectedIndex: selectedIndex),
        ],
        const SizedBox(height: AppSpacing.sm),
        Expanded(child: _AccountFeed(accountId: rows[selectedIndex].id)),
      ],
    );
  }
}

/// A single account rendered as a bigger, wallet-style card. Tapping it opens
/// the existing [AccountDetailsScreen] for edit/archive — card view is an
/// additional way to browse, not a replacement for that screen.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.row, required this.balanceMinor});

  final FinancialAccountRow row;
  final int balanceMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    return Card(
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AccountDetailsScreen(accountId: row.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(accountTypeIcon(row.type), color: colors.mutedText),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              Text(
                accountTypeLabel(row.type),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedText,
                ),
              ),
              Text(
                formatMinorUnits(
                  balanceMinor,
                  symbol: currencySymbol(row.currency),
                ),
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live transactions/transfers feed for one account, reusing the same
/// [TransactionFilter] and [TransactionTile] the Transactions tab already
/// uses — no new query layer.
class _AccountFeed extends ConsumerWidget {
  const _AccountFeed({required this.accountId});

  final String accountId;

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
    final filter = TransactionFilter(accountId: accountId);

    final matched =
        rows
            .where(
              (row) => filter.matches(
                row,
                accountName: accountNames[row.accountId] ?? row.accountId,
                destinationAccountName: row.destinationAccountId == null
                    ? null
                    : accountNames[row.destinationAccountId],
                categoryName: categoriesById[row.categoryId]?.name,
              ),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    if (matched.isEmpty) {
      return const EmptyState(
        icon: Icons.swap_horiz,
        title: 'No transactions yet',
        message: 'This account has no transactions or transfers yet.',
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
          destinationAccountName: row.destinationAccountId == null
              ? null
              : accountNames[row.destinationAccountId] ??
                    row.destinationAccountId,
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
