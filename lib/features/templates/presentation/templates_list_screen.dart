import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../transactions/domain/transaction_type.dart';
import '../../transactions/presentation/transaction_form_screen.dart';
import 'template_form_screen.dart';

/// Saved transaction templates (docs/ROADMAP.md §8.2).
///
/// Tapping a template opens the transaction form pre-filled with its preset
/// values, for the user to review and save — using a template never creates a
/// transaction by itself. The menu on each row manages the template itself
/// (edit/delete), kept separate from that "use" tap the same way a budget
/// card's menu stays independent of opening its history.
class TemplatesListScreen extends ConsumerWidget {
  const TemplatesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Templates')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TemplateFormScreen()),
        ),
        tooltip: 'Add template',
        child: const Icon(Icons.add),
      ),
      body: templates.when(
        data: (rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.bolt_outlined,
                title: 'No templates yet',
                message:
                    'Save a preset for a transaction you enter often, like a '
                    'subscription or a regular bill.',
                action: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TemplateFormScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add template'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
                children: [
                  for (final row in rows) _TemplateCard(template: row),
                ],
              ),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(templatesStreamProvider),
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

class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({required this.template});

  final TransactionTemplateRow template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    final parts = <String>[
      _typeLabel(template.type),
      if (template.amountMinor != null) formatMinorUnits(template.amountMinor!),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TransactionFormScreen(template: template),
                ),
              ),
              child: MergeSemantics(
                child: ListTile(
                  title: Text(template.name),
                  subtitle: Text(
                    parts.join(' · '),
                    style: TextStyle(color: colors.mutedText),
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenu(context, ref, value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    if (value == 'edit') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TemplateFormScreen(initial: template),
        ),
      );
      return;
    }
    if (value == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this template?'),
          content: const Text(
            'This only removes the preset. Transactions you created from it '
            'are not affected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      try {
        await ref.read(templateControllerProvider).delete(template.id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Template deleted')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
        }
      }
    }
  }

  static String _typeLabel(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'Income';
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.transfer:
        return 'Transfer';
      case TransactionType.loanReceipt:
      case TransactionType.loanPayment:
        return 'Loan';
      case TransactionType.investmentContribution:
      case TransactionType.investmentPayout:
      case TransactionType.investmentWithdrawal:
        return 'Investment';
      case TransactionType.savingsContribution:
      case TransactionType.savingsWithdrawal:
        return 'Savings Goal';
    }
  }
}
