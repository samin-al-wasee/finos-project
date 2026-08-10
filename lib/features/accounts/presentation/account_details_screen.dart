import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/account_controller.dart';
import '../domain/account_status.dart';
import 'account_form_screen.dart';
import 'account_type_label.dart';

/// Details for a single account with edit and archive/restore actions.
///
/// Resolves [accountId] from the shared accounts stream so edits made on the
/// form screen appear here automatically on return.
class AccountDetailsScreen extends ConsumerWidget {
  const AccountDetailsScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account details')),
      body: accounts.when(
        data: (rows) {
          for (final row in rows) {
            if (row.id == accountId) return _DetailsBody(account: row);
          }
          return const EmptyState(
            icon: Icons.search_off,
            title: 'Account not found',
            message: 'This account may have been removed.',
          );
        },
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
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

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({required this.account});

  final FinancialAccountRow account;

  bool get _isArchived => account.status == AccountStatus.archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final controller = ref.read(accountControllerProvider);
    // Live balance (opening balance + net transaction impact), so the headline
    // reflects recent transactions instead of the balance at creation time.
    final balances = ref.watch(accountBalancesProvider);
    final balanceMinor =
        balances.valueOrNull?[account.id] ?? account.openingBalanceMinor;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.lg),
        Icon(accountTypeIcon(account.type), size: 48, color: colors.mutedText),
        const SizedBox(height: AppSpacing.md),
        Text(
          account.name,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          accountTypeLabel(account.type),
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedText),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          formatMinorUnits(
            balanceMinor,
            symbol: currencySymbol(account.currency),
          ),
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        Card(
          child: Column(
            children: [
              _DetailRow(
                label: 'Balance type',
                value: _isArchived ? 'Archived' : 'Active',
                valueColor: _isArchived ? colors.warning : colors.success,
              ),
              const Divider(
                height: 1,
                indent: AppSpacing.lg,
                endIndent: AppSpacing.lg,
              ),
              _DetailRow(label: 'Currency', value: account.currency),
              const Divider(
                height: 1,
                indent: AppSpacing.lg,
                endIndent: AppSpacing.lg,
              ),
              _DetailRow(
                label: 'Created',
                value: _formatDate(account.createdAt),
              ),
              const Divider(
                height: 1,
                indent: AppSpacing.lg,
                endIndent: AppSpacing.lg,
              ),
              _DetailRow(
                label: 'Last updated',
                value: _formatDate(account.updatedAt),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AccountFormScreen(initial: account),
              ),
            );
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit'),
        ),
        const SizedBox(height: AppSpacing.md),
        _isArchived
            ? FilledButton.tonalIcon(
                onPressed: () => _confirmRestore(context, controller),
                icon: const Icon(Icons.unarchive_outlined),
                label: const Text('Restore'),
              )
            : FilledButton.tonalIcon(
                onPressed: () => _confirmArchive(context, controller),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive'),
              ),
      ],
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    AccountController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive this account?'),
        content: const Text(
          'Archived accounts stay on record but are hidden from the '
          'active list. You can restore it anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await controller.archive(account.id);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account archived')));
    }
  }

  Future<void> _confirmRestore(
    BuildContext context,
    AccountController controller,
  ) async {
    await controller.restore(account.id);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account restored')));
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats a [DateTime] as a plain `d MMM yyyy` string without the `intl`
/// dependency (docs/DEVELOPMENT.md §49).
String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
