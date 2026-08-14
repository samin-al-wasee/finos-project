import 'package:flutter/material.dart';

import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/savings_goal_progress.dart';

/// What [SavingsGoalContributionDialog] collects.
class SavingsGoalContributionResult {
  const SavingsGoalContributionResult({
    required this.amountMinor,
    required this.date,
  });

  final int amountMinor;
  final DateTime date;
}

/// Collects a contribution amount and its date.
///
/// Unlike a withdrawal, there is no upper cap — saving beyond the target is
/// ordinary (docs/adr/011-savings-goals.md §3).
class SavingsGoalContributionDialog extends StatefulWidget {
  const SavingsGoalContributionDialog({super.key, required this.progress});

  final SavingsGoalProgress progress;

  /// Opens the dialog and returns what the user entered, or `null` if
  /// cancelled.
  static Future<SavingsGoalContributionResult?> show(
    BuildContext context, {
    required SavingsGoalProgress progress,
  }) {
    return showDialog<SavingsGoalContributionResult>(
      context: context,
      builder: (context) =>
          SavingsGoalContributionDialog(progress: progress),
    );
  }

  @override
  State<SavingsGoalContributionDialog> createState() =>
      _SavingsGoalContributionDialogState();
}

class _SavingsGoalContributionDialogState
    extends State<SavingsGoalContributionDialog> {
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
    final symbol = currencySymbol(widget.progress.goal.currency);

    return AlertDialog(
      title: const Text('Add contribution'),
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
        FilledButton(onPressed: _submit, child: const Text('Contribute')),
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
      firstDate: widget.progress.goal.startDate,
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      SavingsGoalContributionResult(
        amountMinor: parseMinorUnits(_amountController.text.trim()),
        date: _date,
      ),
    );
  }
}
