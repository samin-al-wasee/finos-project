import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../categories/presentation/categories_list_screen.dart';
import '../domain/account_status.dart';
import 'account_details_screen.dart';
import 'account_form_screen.dart';
import 'account_type_label.dart';

/// Accounts tab content.
///
/// Watches the accounts stream and groups active accounts above archived ones.
/// A floating action button and the empty state both lead to the account form.
class AccountsListScreen extends ConsumerWidget {
  const AccountsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider);
    // Live balances (opening balance + net transaction impact), so the list
    // reflects recent transactions instead of the balance at creation time.
    final balances = ref.watch(accountBalancesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          // Category management entry point. The transaction form links to the
          // category list too, but this stays until a Settings screen exists.
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Categories',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CategoriesListScreen(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        tooltip: 'Add account',
        child: const Icon(Icons.add),
      ),
      body: accounts.when(
        data: (rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No accounts yet',
                message:
                    'Add your bank accounts, wallets, and cards to start '
                    'tracking where your money lives.',
                action: FilledButton.icon(
                  onPressed: () => _openForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add account'),
                ),
              )
            : _AccountList(
                rows: rows,
                balances: balances.valueOrNull ?? const <String, int>{},
              ),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(accountsStreamProvider),
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AccountFormScreen()));
  }
}

/// Groups [rows] into active and archived sections with a shared tile builder.
class _AccountList extends StatelessWidget {
  const _AccountList({required this.rows, required this.balances});

  final List<FinancialAccountRow> rows;

  /// Live balance (opening + net transaction impact) per account id.
  final Map<String, int> balances;

  @override
  Widget build(BuildContext context) {
    final active = rows.where((r) => r.status == AccountStatus.active).toList();
    final archived = rows
        .where((r) => r.status == AccountStatus.archived)
        .toList();

    final children = <Widget>[
      if (active.isEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'No active accounts',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        )
      else
        for (final row in active)
          _AccountTile(
            row: row,
            balanceMinor: balances[row.id] ?? row.openingBalanceMinor,
          ),
      if (archived.isNotEmpty) ...[
        const _SectionHeader(title: 'Archived'),
        for (final row in archived)
          _AccountTile(
            row: row,
            balanceMinor: balances[row.id] ?? row.openingBalanceMinor,
            archived: true,
          ),
      ],
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.row,
    required this.balanceMinor,
    this.archived = false,
  });

  final FinancialAccountRow row;

  /// Live balance for this account (opening balance + net transaction impact).
  final int balanceMinor;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    return ListTile(
      leading: CircleAvatar(child: Icon(accountTypeIcon(row.type))),
      title: Text(row.name),
      subtitle: Text(accountTypeLabel(row.type)),
      trailing: Text(
        formatMinorUnits(balanceMinor, symbol: currencySymbol(row.currency)),
        style: theme.textTheme.titleSmall?.copyWith(
          color: archived ? colors.mutedText : null,
        ),
      ),
      enabled: !archived,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AccountDetailsScreen(accountId: row.id),
        ),
      ),
    );
  }
}
