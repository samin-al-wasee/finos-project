import 'package:flutter/material.dart';

import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/investment_progress.dart';

/// What [InvestmentWithdrawalDialog] collects.
class InvestmentWithdrawalResult {
  const InvestmentWithdrawalResult({
    required this.amountMinor,
    required this.date,
  });

  final int amountMinor;
  final DateTime date;
}

/// Collects an early-withdrawal amount and its date, capped at
/// [InvestmentProgress.remainingPrincipalMinor] — over-withdrawal is
/// rejected, the same rule `RepaymentDialog` applies via
/// `LoanProgress.maxRepaymentMinor` (docs/adr/010-investment-early-withdrawal.md).
class InvestmentWithdrawalDialog extends StatefulWidget {
  const InvestmentWithdrawalDialog({super.key, required this.progress});

  final InvestmentProgress progress;

  /// Opens the dialog and returns what the user entered, or `null` if
  /// cancelled.
  static Future<InvestmentWithdrawalResult?> show(
    BuildContext context, {
    required InvestmentProgress progress,
  }) {
    return showDialog<InvestmentWithdrawalResult>(
      context: context,
      builder: (context) => InvestmentWithdrawalDialog(progress: progress),
    );
  }

  @override
  State<InvestmentWithdrawalDialog> createState() =>
      _InvestmentWithdrawalDialogState();
}

class _InvestmentWithdrawalDialogState
    extends State<InvestmentWithdrawalDialog> {
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
    final maxWithdrawal = widget.progress.maxWithdrawalMinor;

    return AlertDialog(
      title: const Text('Withdraw funds'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the amount you actually withdrew. Up to '
              '${formatMinorUnits(maxWithdrawal, symbol: symbol)} remains.',
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
        FilledButton(onPressed: _submit, child: const Text('Withdraw')),
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
    if (minor > widget.progress.maxWithdrawalMinor) {
      return 'That is more than what remains';
    }
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
      InvestmentWithdrawalResult(
        amountMinor: parseMinorUnits(_amountController.text.trim()),
        date: _date,
      ),
    );
  }
}
