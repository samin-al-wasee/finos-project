import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../accounts/domain/account_status.dart';
import '../../categories/domain/category_status.dart';
import '../../categories/domain/category_type.dart';
import '../../transactions/domain/transaction_type.dart';
import '../domain/recurrence_frequency.dart';
import '../domain/recurring_draft.dart';

/// Add/edit form for a recurring transaction rule (docs/ROADMAP.md §8.1).
///
/// Unlike a template, a rule generates transactions unattended, so its amount
/// and account are required rather than optional (docs/DATA_MODEL.md §27).
/// [draft] pre-fills a *new* rule from quick entry (docs/ARCHITECTURE.md,
/// "quick entry") — a one-off, unsaved seed, ignored when [initial] is set.
class RecurringTransactionFormScreen extends ConsumerStatefulWidget {
  const RecurringTransactionFormScreen({super.key, this.initial, this.draft});

  /// The rule being edited, or `null` when creating a new one.
  final RecurringTransactionRow? initial;

  /// A quick-entry seed to pre-fill a new rule from, or `null`.
  final RecurringDraft? draft;

  @override
  ConsumerState<RecurringTransactionFormScreen> createState() =>
      _RecurringTransactionFormScreenState();
}

class _RecurringTransactionFormScreenState
    extends ConsumerState<RecurringTransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  TransactionType _type = TransactionType.expense;
  String? _accountId;
  String? _destinationAccountId;
  String? _categoryId;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  late DateTime _startDate;
  DateTime? _endDate;

  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final draft = initial == null ? widget.draft : null;

    final presetAmountMinor = initial?.amountMinor ?? draft?.amountMinor;
    _nameController = TextEditingController(
      text: initial?.name ?? draft?.name ?? '',
    );
    _amountController = TextEditingController(
      text: presetAmountMinor == null
          ? ''
          : minorUnitsToInput(presetAmountMinor),
    );
    _notesController = TextEditingController(
      text: initial?.description ?? draft?.description ?? '',
    );
    _type = initial?.type ?? draft?.type ?? TransactionType.expense;
    _accountId = initial?.accountId ?? draft?.accountId;
    _destinationAccountId =
        initial?.destinationAccountId ?? draft?.destinationAccountId;
    _categoryId = initial?.categoryId ?? draft?.categoryId;
    _frequency =
        initial?.frequency ?? draft?.frequency ?? RecurrenceFrequency.monthly;
    _startDate = initial?.startDate ?? draft?.startDate ?? DateTime.now();
    _endDate = initial?.endDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsStreamProvider);
    final categories = ref.watch(categoriesStreamProvider);

    final activeAccounts = (accounts.valueOrNull ?? [])
        .where((a) => a.status == AccountStatus.active)
        .toList();
    final activeCategories = (categories.valueOrNull ?? [])
        .where((c) => c.status == CategoryStatus.active)
        .toList();
    final filteredCategories = activeCategories.where((c) {
      if (_type == TransactionType.transfer) return false;
      return c.type ==
          (_type == TransactionType.income
              ? CategoryType.income
              : CategoryType.expense);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? 'Edit recurring transaction'
              : 'New recurring transaction',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Netflix',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a name for this recurring transaction'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),

              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Income'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment(
                    value: TransactionType.transfer,
                    label: Text('Transfer'),
                    icon: Icon(Icons.swap_horiz),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (set) {
                  if (set.isEmpty) return;
                  setState(() {
                    _type = set.first;
                    if (_type == TransactionType.transfer) {
                      _categoryId = null;
                    } else {
                      _destinationAccountId = null;
                    }
                  });
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: 'e.g. 10000',
                  border: OutlineInputBorder(),
                ),
                validator: _validateAmount,
              ),
              const SizedBox(height: AppSpacing.lg),

              DropdownButtonFormField<String>(
                // Guarded against the stream not having loaded yet: an
                // initialValue absent from items would trip
                // DropdownButtonFormField's "exactly one match" assertion.
                initialValue: activeAccounts.any((a) => a.id == _accountId)
                    ? _accountId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Account',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final a in activeAccounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (value) => setState(() {
                  _accountId = value;
                  if (_destinationAccountId == value) {
                    _destinationAccountId = null;
                  }
                }),
                validator: (value) =>
                    value == null ? 'Choose an account' : null,
              ),

              if (_type == TransactionType.transfer) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue:
                      activeAccounts.any((a) => a.id == _destinationAccountId)
                      ? _destinationAccountId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'To',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final a in activeAccounts)
                      if (a.id != _accountId)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (value) =>
                      setState(() => _destinationAccountId = value),
                  validator: (value) =>
                      value == null ? 'Choose a destination account' : null,
                ),
              ],

              if (_type != TransactionType.transfer) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String?>(
                  initialValue:
                      filteredCategories.any((c) => c.id == _categoryId)
                      ? _categoryId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final c in filteredCategories)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
              ],

              // ── Recurrence ──────────────────────────────────────────────
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<RecurrenceFrequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Repeats',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final frequency in RecurrenceFrequency.values)
                    DropdownMenuItem(
                      value: frequency,
                      child: Text(recurrenceFrequencyLabel(frequency)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _frequency = value);
                },
              ),

              const SizedBox(height: AppSpacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Starts on'),
                trailing: Text(
                  formatDate(_startDate),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                onTap: _pickStartDate,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ends on (optional)'),
                onTap: _pickEndDate,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _endDate == null ? 'Never' : formatDate(_endDate!),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (_endDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear end date',
                        onPressed: () => setState(() => _endDate = null),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _notesController,
                textInputAction: TextInputAction.done,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _isEditing
                              ? 'Save changes'
                              : 'Add recurring transaction',
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amountMinor = parseMinorUnits(_amountController.text.trim());
    final name = _nameController.text.trim();
    final notes = _notesController.text.trim();

    setState(() => _saving = true);
    try {
      final controller = ref.read(recurringTransactionControllerProvider);
      if (_isEditing) {
        await controller.update(
          id: widget.initial!.id,
          name: name,
          type: _type,
          amountMinor: amountMinor,
          accountId: _accountId!,
          destinationAccountId: _destinationAccountId,
          categoryId: _categoryId,
          description: notes,
          frequency: _frequency,
          startDate: _startDate,
          endDate: _endDate,
        );
      } else {
        await controller.create(
          name: name,
          type: _type,
          amountMinor: amountMinor,
          accountId: _accountId!,
          destinationAccountId: _destinationAccountId,
          categoryId: _categoryId,
          description: notes,
          frequency: _frequency,
          startDate: _startDate,
          endDate: _endDate,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
