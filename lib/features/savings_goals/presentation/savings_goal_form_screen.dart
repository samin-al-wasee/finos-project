import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../accounts/domain/account_status.dart';
import '../application/savings_goal_controller.dart';

/// Add/edit form for a savings goal (docs/adr/011-savings-goals.md).
///
/// When editing, the linked account and currency are fixed: changing either
/// would leave every recorded contribution/withdrawal describing a goal that
/// no longer exists. The name, target amount, deadline, and note stay
/// editable — the target is only ever compared against the derived current
/// amount, never summed into it, so changing it cannot corrupt anything
/// derived.
class SavingsGoalFormScreen extends ConsumerStatefulWidget {
  const SavingsGoalFormScreen({super.key, this.initial});

  /// The goal being edited, or `null` when creating a new one.
  final SavingsGoalRow? initial;

  @override
  ConsumerState<SavingsGoalFormScreen> createState() =>
      _SavingsGoalFormScreenState();
}

class _SavingsGoalFormScreenState extends ConsumerState<SavingsGoalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _targetController;
  late final TextEditingController _noteController;
  late DateTime _startDate;
  DateTime? _deadlineDate;
  String? _accountId;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;

    _nameController = TextEditingController(text: initial?.name ?? '');
    _targetController = TextEditingController(
      text: initial == null
          ? ''
          : minorUnitsToInput(initial.targetAmountMinor),
    );
    _noteController = TextEditingController(text: initial?.description ?? '');
    _startDate = initial?.startDate ?? DateTime.now();
    _deadlineDate = initial?.deadlineDate;
    _accountId = initial?.accountId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(savingsGoalControllerProvider);

    final accounts = ref
        .watch(accountsStreamProvider)
        .maybeWhen(
          data: (rows) =>
              rows.where((a) => a.status == AccountStatus.active).toList(),
          orElse: () => <FinancialAccountRow>[],
        );

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit goal' : 'Add goal')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // ── Name ─────────────────────────────────────────────────────
              TextFormField(
                controller: _nameController,
                autofocus: !_isEditing,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Goal name',
                  hintText: 'e.g. Emergency Fund, New Laptop',
                  border: OutlineInputBorder(),
                ),
                validator: _validateName,
              ),

              // ── Target amount ───────────────────────────────────────────
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _targetController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Target amount',
                  hintText: 'e.g. 500000',
                  border: OutlineInputBorder(),
                ),
                validator: _validateTarget,
              ),

              // ── Linked account ───────────────────────────────────────────
              if (!_isEditing) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String?>(
                  initialValue: _accountId,
                  decoration: const InputDecoration(
                    labelText: 'Account',
                    helperText:
                        'Contributions leave this account; withdrawals '
                        'return to it.',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in accounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _accountId = value),
                  validator: (value) =>
                      value == null ? 'Choose an account' : null,
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
                title: const Text('Deadline'),
                trailing: Text(
                  _deadlineDate == null ? 'None' : formatDate(_deadlineDate!),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                onTap: _pickDeadlineDate,
              ),
              if (_deadlineDate != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _deadlineDate = null),
                    child: const Text('Clear deadline'),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'Save changes' : 'Add goal'),
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
    if (name.isEmpty) return 'Enter a name for this goal';
    if (name.length > 100) return 'Name must be 100 characters or fewer';
    return null;
  }

  String? _validateTarget(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter a target amount';
    try {
      if (parseMinorUnits(input) <= 0) {
        return 'Target amount must be greater than zero';
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

  Future<void> _pickDeadlineDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadlineDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime(DateTime.now().year + 30),
    );
    if (picked != null) setState(() => _deadlineDate = picked);
  }

  // ── Save ────────────────────────────────────────────────────────────────

  Future<void> _save(SavingsGoalController controller) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await controller.update(
          id: widget.initial!.id,
          name: _nameController.text,
          targetAmountMinor: parseMinorUnits(_targetController.text.trim()),
          deadlineDate: _deadlineDate,
          description: _noteController.text.trim(),
        );
      } else {
        await controller.create(
          name: _nameController.text,
          targetAmountMinor: parseMinorUnits(_targetController.text.trim()),
          accountId: _accountId!,
          startDate: _startDate,
          deadlineDate: _deadlineDate,
          description: _noteController.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save the goal: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
