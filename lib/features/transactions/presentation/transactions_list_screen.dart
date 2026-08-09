import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/transaction_controller.dart';
import 'transaction_form_screen.dart';
import 'transaction_tile.dart';

/// Transactions tab content (FR-02).
///
/// Watches the transactions stream and groups rows into date sections
/// ("Today" / "Yesterday" / calendar date). A floating action button opens the
/// create form; per-tile popup menus offer edit and delete (with confirmation
/// — docs/UI_DESIGN.md §35).
class TransactionsListScreen extends ConsumerWidget {
  const TransactionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(transactionsStreamProvider);
    final accounts = ref.watch(accountsStreamProvider);
    final categories = ref.watch(categoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        tooltip: 'Add transaction',
        child: const Icon(Icons.add),
      ),
      body: transactions.when(
        data: (rows) => rows.isEmpty
            ? const EmptyState(
                icon: Icons.swap_horiz,
                title: 'No transactions yet',
                message: 'Add your first transaction to start tracking money.',
                action: _AddTransactionButton(),
              )
            : accounts.when(
                data: (accountRows) => categories.when(
                  data: (categoryRows) => _TransactionList(
                    rows: rows,
                    accounts: accountRows,
                    categories: categoryRows,
                  ),
                  error: (e, _) => _ErrorState(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(categoriesStreamProvider),
                  ),
                  loading: () => const _LoadingState(),
                ),
                error: (e, _) => _ErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(accountsStreamProvider),
                ),
                loading: () => const _LoadingState(),
              ),
        error: (e, _) => _ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(transactionsStreamProvider),
        ),
        loading: () => const _LoadingState(),
      ),
    );
  }

  void _openForm(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TransactionFormScreen()));
  }
}

/// Groups [rows] into date sections and renders one tile per transaction.
class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.rows,
    required this.accounts,
    required this.categories,
  });

  final List<TransactionRow> rows;
  final List<FinancialAccountRow> accounts;
  final List<CategoryRow> categories;

  @override
  Widget build(BuildContext context) {
    final accountNames = {for (final a in accounts) a.id: a.name};
    final categoriesById = {for (final c in categories) c.id: c};

    // Group by calendar day, preserving the newest-first order within and
    // across sections.
    final sections = <String, List<TransactionRow>>{};
    final order = <String>[];
    for (final row in rows) {
      final label = dateLabel(row.date);
      if (!sections.containsKey(label)) {
        sections[label] = [];
        order.add(label);
      }
      sections[label]!.add(row);
    }

    final children = <Widget>[];
    for (final label in order) {
      children.add(_SectionHeader(title: label));
      for (final row in sections[label]!) {
        final category = row.categoryId == null
            ? null
            : categoriesById[row.categoryId];
        children.add(
          TransactionTile(
            key: ValueKey(row.id),
            transaction: row,
            accountName: accountNames[row.accountId] ?? row.accountId,
            destinationAccountName: row.destinationAccountId == null
                ? null
                : accountNames[row.destinationAccountId] ??
                    row.destinationAccountId,
            categoryName: category?.name,
            categoryIconKey: category?.icon,
            onTap: () => _openEdit(context, row),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: children,
    );
  }

  void _openEdit(BuildContext context, TransactionRow row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionFormScreen(initial: row),
      ),
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

/// The button inside the empty state, kept as its own widget so the empty
/// state stays const.
class _AddTransactionButton extends StatelessWidget {
  const _AddTransactionButton();

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const TransactionFormScreen(),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Add transaction'),
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
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      message: message,
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    );
  }
}
