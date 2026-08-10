import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../accounts/domain/account_status.dart';
import '../application/loan_controller.dart';
import '../domain/loan_direction.dart';
import 'loan_labels.dart';

/// Add/edit form for a loan (FR-06).
///
/// When editing, only the name, due date, and note can change. Direction,
/// principal, and disbursement account are fixed at creation: altering them would
/// leave the origination transaction and every derived figure describing a loan
/// that no longer exists (ADR-004).
class LoanFormScreen extends ConsumerStatefulWidget {
  const LoanFormScreen({super.key, this.initial});

  /// The loan being edited, or `null` when creating a new one.
  final LoanRow? initial;

  @override
  ConsumerState<LoanFormScreen> createState() => _LoanFormScreenState();
}

class _LoanFormScreenState extends ConsumerState<LoanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late LoanDirection _direction;
  late DateTime _startDate;
  DateTime? _dueDate;
  String? _disbursementAccountId;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _amountController = TextEditingController(
      text: initial == null ? '' : minorUnitsToInput(initial.principalMinor),
    );
    _noteController = TextEditingController(text: initial?.description ?? '');
    _direction = initial?.type ?? LoanDirection.borrowed;
    _startDate = initial?.startDate ?? DateTime.now();
    _dueDate = initial?.dueDate;
    _disbursementAccountId = initial?.disbursementAccountId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(loanControllerProvider);
    final colors = Theme.of(context).extension<FinosColors>()!;

    final accounts = ref
        .watch(accountsStreamProvider)
        .maybeWhen(
          data: (rows) =>
              rows.where((a) => a.status == AccountStatus.active).toList(),
          orElse: () => <FinancialAccountRow>[],
        );

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit loan' : 'Add loan')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // ── Direction ───────────────────────────────────────────────
              if (!_isEditing) ...[
                SegmentedButton<LoanDirection>(
                  segments: [
                    for (final direction in LoanDirection.values)
                      ButtonSegment(
                        value: direction,
                        label: Text(loanDirectionOption(direction)),
                      ),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (selection) =>
                      setState(() => _direction = selection.first),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // ── Counterparty ────────────────────────────────────────────
              TextFormField(
                controller: _nameController,
                autofocus: !_isEditing,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: _direction == LoanDirection.borrowed
                      ? 'Who I owe'
                      : 'Who owes me',
                  hintText: 'e.g. John, or Bank Loan',
                  border: const OutlineInputBorder(),
                ),
                validator: _validateName,
              ),

              // ── Principal ───────────────────────────────────────────────
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _amountController,
                enabled: !_isEditing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText: 'e.g. 20000',
                  border: const OutlineInputBorder(),
                  helperText: _isEditing
                      ? 'The amount is fixed once a loan is created'
                      : null,
                ),
                validator: _isEditing ? null : _validateAmount,
              ),

              // ── Disbursement ────────────────────────────────────────────
              if (!_isEditing) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String?>(
                  initialValue: _disbursementAccountId,
                  decoration: const InputDecoration(
                    labelText: 'Money moved through',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('No account — this loan already existed'),
                    ),
                    for (final account in accounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _disbursementAccountId = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _disbursementAccountId == null
                      ? 'No money moves now. Choose this for a loan that '
                            'started before you used FinOS.'
                      : _direction == LoanDirection.borrowed
                      ? 'The amount will be added to that account.'
                      : 'The amount will be taken out of that account.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.mutedText),
                ),
              ],

              // ── Dates ───────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: !_isEditing,
                title: const Text('Start date'),
                trailing: Text(
                  formatDate(_startDate),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                onTap: _isEditing ? null : _pickStartDate,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Due date'),
                trailing: Text(
                  _dueDate == null ? 'None' : formatDate(_dueDate!),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                onTap: _pickDueDate,
              ),
              if (_dueDate != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _dueDate = null),
                    child: const Text('Clear due date'),
                  ),
                ),

              // ── Note ────────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _noteController,
                textInputAction: TextInputAction.done,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),

              // ── Save ────────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _saving ? null : () => _save(controller),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'Save changes' : 'Add loan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Validation ──────────────────────────────────────────────────────────

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter who the loan is with';
    if (name.length > 100) return 'Name must be 100 characters or fewer';
    return null;
  }

  String? _validateAmount(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter an amount';
    try {
      if (parseMinorUnits(input) <= 0) {
        return 'Amount must be greater than zero';
      }
    } on FormatException {
      return 'Enter a valid amount';
    }
    return null;
  }

  // ── Date pickers ────────────────────────────────────────────────────────

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime(DateTime.now().year + 30),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  // ── Save ────────────────────────────────────────────────────────────────

  Future<void> _save(LoanController controller) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await controller.update(
          id: widget.initial!.id,
          name: _nameController.text,
          dueDate: _dueDate,
          description: _noteController.text.trim(),
        );
      } else {
        await controller.create(
          direction: _direction,
          name: _nameController.text,
          principalMinor: parseMinorUnits(_amountController.text.trim()),
          disbursementAccountId: _disbursementAccountId,
          startDate: _startDate,
          dueDate: _dueDate,
          description: _noteController.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save the loan: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
