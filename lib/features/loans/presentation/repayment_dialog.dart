import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/loan_draft.dart';
import '../domain/loan_progress.dart';
import 'loan_labels.dart';

/// What [RepaymentDialog] collects.
class RepaymentResult {
  const RepaymentResult({
    required this.amountMinor,
    required this.accountId,
    required this.date,
  });

  final int amountMinor;
  final String accountId;
  final DateTime date;
}

/// Collects a repayment amount, the account it moves through, and its date.
///
/// Public (rather than living privately inside [LoanDetailsScreen]) so quick
/// entry (docs/ARCHITECTURE.md, "quick entry") can open it too, pre-filled
/// via [draft].
class RepaymentDialog extends StatefulWidget {
  const RepaymentDialog({
    super.key,
    required this.progress,
    required this.accounts,
    this.draft,
  });

  final LoanProgress progress;
  final List<FinancialAccountRow> accounts;

  /// A quick-entry seed to pre-fill this dialog from, or `null`.
  final RepaymentDraft? draft;

  /// Opens the dialog and returns what the user entered, or `null` if
  /// cancelled.
  static Future<RepaymentResult?> show(
    BuildContext context, {
    required LoanProgress progress,
    required List<FinancialAccountRow> accounts,
    RepaymentDraft? draft,
  }) {
    return showDialog<RepaymentResult>(
      context: context,
      builder: (context) =>
          RepaymentDialog(progress: progress, accounts: accounts, draft: draft),
    );
  }

  @override
  State<RepaymentDialog> createState() => _RepaymentDialogState();
}

class _RepaymentDialogState extends State<RepaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late String _accountId;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    // Pre-filled with the full outstanding amount by default: settling a loan
    // completely is the most common repayment, and it is also the maximum
    // allowed. A quick-entry draft's amount, if given, overrides that.
    _amountController = TextEditingController(
      text: minorUnitsToInput(
        widget.draft?.amountMinor ?? widget.progress.outstandingMinor,
      ),
    );
    final draftAccountId = widget.draft?.accountId;
    _accountId =
        draftAccountId != null &&
            widget.accounts.any((a) => a.id == draftAccountId)
        ? draftAccountId
        : widget.accounts.first.id;
    _date = widget.draft?.date ?? DateTime.now();
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
      RepaymentResult(
        amountMinor: parseMinorUnits(_amountController.text.trim()),
        accountId: _accountId,
        date: _date,
      ),
    );
  }
}
