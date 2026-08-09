import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';

/// Home tab content.
///
/// Watches the accounts stream and shows a placeholder until the first account
/// is created (Phase 1). The empty state intentionally provides no "create"
/// action yet because account management is not part of this phase.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('FinOS')),
      body: accounts.when(
        data: (rows) => rows.isEmpty
            ? const EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No accounts yet',
                message:
                    'Accounts will appear here once you add your first '
                    'financial source in Phase 1.',
              )
            : const SizedBox.shrink(),
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
