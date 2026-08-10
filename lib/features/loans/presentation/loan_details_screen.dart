import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../accounts/domain/account_status.dart';
import '../domain/loan_progress.dart';
import 'loan_form_screen.dart';
import 'loan_labels.dart';

/// Loan detail screen (docs/UI_DESIGN.md §22).
///
/// Shows the original amount, what has been paid, and what remains, then the
/// individual repayments. Recording a repayment happens here rather than in the
/// transaction form, so the amount can be checked against what is outstanding.
class LoanDetailsScreen extends ConsumerWidget {
  const LoanDetailsScreen({super.key, required this.loanId});

  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(loanProgressByIdProvider(loanId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loan'),
        actions: [
          progress.maybeWhen(
            data: (value) => value == null
                ? const SizedBox.shrink()
                : _LoanMenu(progress: value),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: progress.when(
        data: (value) => value == null
            ? const Center(child: Text('This loan no longer exists.'))
            : _Details(progress: value),
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.progress});

  final LoanProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final loan = progress.loan;
    final symbol = currencySymbol(loan.currency);
    final standing = progress.standing();
    final movements = ref.watch(loanMovementsProvider(loan.id));

    // Watched, not read on demand: a StreamProvider that nothing is listening to
    // reports as loading, which would make the repayment flow believe there are
    // no accounts at all.
    final accounts = ref
        .watch(accountsStreamProvider)
        .maybeWhen(
          data: (rows) =>
              rows.where((a) => a.status == AccountStatus.active).toList(),
          orElse: () => <FinancialAccountRow>[],
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loan.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                loanDirectionLabel(loan.type),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.mutedText,
                ),
              ),
            ],
          ),
        ),

        // ── Figures ───────────────────────────────────────────────────────
        _AmountRow(
          label: 'Original amount',
          value: formatMinorUnits(progress.principalMinor, symbol: symbol),
        ),
        _AmountRow(
          label: 'Paid',
          value: formatMinorUnits(progress.repaidMinor, symbol: symbol),
        ),
        _AmountRow(
          label: 'Remaining',
          value: formatMinorUnits(progress.outstandingMinor, symbol: symbol),
          emphasise: true,
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: progress.repaidFraction,
              minHeight: AppSpacing.sm,
              backgroundColor: colors.border,
              color: standing == LoanStanding.paid
                  ? colors.success
                  : colors.transfer,
              semanticsLabel: '${loan.name} repaid',
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // The standing is stated in words, never colour alone
              // (AGENTS.md §21).
              Text(
                loanStandingLabel(standing),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: standing == LoanStanding.overdue
                      ? colors.error
                      : standing == LoanStanding.paid
                      ? colors.success
                      : colors.mutedText,
                ),
              ),
              if (loan.dueDate != null)
                Text(
                  'Due ${formatDate(loan.dueDate!)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.mutedText,
                  ),
                ),
            ],
          ),
        ),

        if (loan.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Text(loan.description, style: theme.textTheme.bodyMedium),
          ),

        // ── Record a repayment ────────────────────────────────────────────
        if (!progress.isPaid && !progress.isArchived)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: FilledButton.icon(
              onPressed: () => _recordRepayment(context, ref, accounts),
              icon: const Icon(Icons.add),
              label: Text(repaymentActionLabel(loan.type)),
            ),
          ),

        // ── History ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            'Activity',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.mutedText,
            ),
          ),
        ),
        movements.when(
          data: (rows) => rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Text(
                    'No repayments recorded yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final row in rows)
                      ListTile(
                        leading: const Icon(Icons.handshake_outlined),
                        title: Text(
                          row.description.isEmpty
                              ? 'Movement'
                              : row.description,
                        ),
                        subtitle: Text(formatDate(row.date)),
                        trailing: Text(
                          formatMinorUnits(row.amountMinor, symbol: symbol),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                  ],
                ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(error.toString()),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }

  Future<void> _recordRepayment(
    BuildContext context,
    WidgetRef ref,
    List<FinancialAccountRow> accounts,
  ) async {
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add an active account before recording a repayment'),
        ),
      );
      return;
    }

    final result = await showDialog<_RepaymentInput>(
      context: context,
      builder: (context) =>
          _RepaymentDialog(progress: progress, accounts: accounts),
    );
    if (result == null || !context.mounted) return;

    try {
      await ref
          .read(loanControllerProvider)
          .recordRepayment(
            loanId: progress.loan.id,
            amountMinor: result.amountMinor,
            accountId: result.accountId,
            date: result.date,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Repayment recorded')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not record it: $e')));
      }
    }
  }
}

/// A labelled figure on the details screen.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          Text(
            value,
            style: emphasise
                ? theme.textTheme.titleLarge
                : theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

/// What the repayment dialog collects.
class _RepaymentInput {
  const _RepaymentInput({
    required this.amountMinor,
    required this.accountId,
    required this.date,
  });

  final int amountMinor;
  final String accountId;
  final DateTime date;
}

/// Collects a repayment amount, the account it moves through, and its date.
class _RepaymentDialog extends StatefulWidget {
  const _RepaymentDialog({required this.progress, required this.accounts});

  final LoanProgress progress;
  final List<FinancialAccountRow> accounts;

  @override
  State<_RepaymentDialog> createState() => _RepaymentDialogState();
}

class _RepaymentDialogState extends State<_RepaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late String _accountId;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Pre-filled with the full outstanding amount: settling a loan completely is
    // the most common repayment, and it is also the maximum allowed.
    _amountController = TextEditingController(
      text: minorUnitsToInput(widget.progress.outstandingMinor),
    );
    _accountId = widget.accounts.first.id;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = currencySymbol(widget.progress.loan.currency);

    return AlertDialog(
      title: Text(repaymentActionLabel(widget.progress.direction)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '$symbol ',
                helperText:
                    '${formatMinorUnits(widget.progress.outstandingMinor, symbol: symbol)} outstanding',
                border: const OutlineInputBorder(),
              ),
              validator: _validateAmount,
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(
                labelText: 'Account',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final account in widget.accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _accountId = value);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              trailing: Text(formatDate(_date)),
              onTap: _pickDate,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Record')),
      ],
    );
  }

  String? _validateAmount(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter an amount';
    final int minor;
    try {
      minor = parseMinorUnits(input);
    } on FormatException {
      return 'Enter a valid amount';
    }
    if (minor <= 0) return 'Amount must be greater than zero';
    // Caught here as well as in the controller, so the user sees it before the
    // dialog closes (docs/DATA_MODEL.md §36).
    if (minor > widget.progress.outstandingMinor) {
      return 'That is more than the outstanding amount';
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.progress.loan.startDate,
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _RepaymentInput(
        amountMinor: parseMinorUnits(_amountController.text.trim()),
        accountId: _accountId,
        date: _date,
      ),
    );
  }
}

/// Edit, archive/restore, and delete for a loan.
class _LoanMenu extends ConsumerWidget {
  const _LoanMenu({required this.progress});

  final LoanProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Loan options',
      onSelected: (value) => _handle(context, ref, value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (progress.isArchived)
          const PopupMenuItem(value: 'restore', child: Text('Restore'))
        else
          const PopupMenuItem(value: 'archive', child: Text('Archive')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final controller = ref.read(loanControllerProvider);

    if (value == 'edit') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoanFormScreen(initial: progress.loan),
        ),
      );
      return;
    }

    if (value == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this loan?'),
          content: const Text(
            'This removes the loan and the money movement that created it. '
            'Loans with repayments recorded cannot be deleted — archive them '
            'instead.',
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
      if (confirmed != true || !context.mounted) return;
      try {
        await controller.delete(progress.loan.id);
        if (context.mounted) Navigator.of(context).pop();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
      return;
    }

    try {
      switch (value) {
        case 'archive':
          await controller.archive(progress.loan.id);
        case 'restore':
          await controller.restore(progress.loan.id);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
  }
}
