import 'package:flutter/material.dart';

import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/investment_progress.dart';

/// What [InvestmentPayoutDialog] collects.
class InvestmentPayoutResult {
  const InvestmentPayoutResult({required this.amountMinor, required this.date});

  final int amountMinor;
  final DateTime date;
}

/// Collects a payout amount and its date.
///
/// Unlike a contribution installment, the amount is never pre-filled from a
/// stored figure: real interest/profit is bank-computed, and this app must
/// never guess at money (docs/adr/009-investment-accounting.md). Used for
/// both a routine periodic profit payout and the final maturity payout —
/// [isMaturityPayout] only changes the title and helper text.
class InvestmentPayoutDialog extends StatefulWidget {
  const InvestmentPayoutDialog({
    super.key,
    required this.progress,
    required this.isMaturityPayout,
  });

  final InvestmentProgress progress;
  final bool isMaturityPayout;

  /// Opens the dialog and returns what the user entered, or `null` if
  /// cancelled.
  static Future<InvestmentPayoutResult?> show(
    BuildContext context, {
    required InvestmentProgress progress,
    required bool isMaturityPayout,
  }) {
    return showDialog<InvestmentPayoutResult>(
      context: context,
      builder: (context) => InvestmentPayoutDialog(
        progress: progress,
        isMaturityPayout: isMaturityPayout,
      ),
    );
  }

  @override
  State<InvestmentPayoutDialog> createState() => _InvestmentPayoutDialogState();
}

class _InvestmentPayoutDialogState extends State<InvestmentPayoutDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = currencySymbol(widget.progress.investment.currency);

    return AlertDialog(
      title: Text(
        widget.isMaturityPayout ? 'Confirm maturity payout' : 'Confirm payout',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isMaturityPayout
                  ? 'Enter the total amount actually paid out — principal '
                        'plus any final profit.'
                  : 'Enter the profit amount actually paid out.',
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '$symbol ',
                border: const OutlineInputBorder(),
              ),
              validator: _validateAmount,
            ),
            const SizedBox(height: AppSpacing.sm),
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
        FilledButton(onPressed: _submit, child: const Text('Confirm')),
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
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.progress.investment.startDate,
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      InvestmentPayoutResult(
        amountMinor: parseMinorUnits(_amountController.text.trim()),
        date: _date,
      ),
    );
  }
}
