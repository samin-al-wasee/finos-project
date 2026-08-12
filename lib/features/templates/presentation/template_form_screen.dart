import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../accounts/domain/account_status.dart';
import '../../categories/domain/category_status.dart';
import '../../categories/domain/category_type.dart';
import '../../transactions/domain/transaction_type.dart';
import '../domain/template_draft.dart';

/// Add/edit form for a transaction template (docs/ROADMAP.md §8.2).
///
/// Every field except the name is optional: a template is a preset, not a
/// transaction, so it is free to leave the amount (or account, or category)
/// blank for the user to fill in at the moment they use it. [draft] pre-fills
/// a *new* template from quick entry (docs/ARCHITECTURE.md, "quick entry") —
/// a one-off, unsaved seed, ignored when [initial] is set.
class TemplateFormScreen extends ConsumerStatefulWidget {
  const TemplateFormScreen({super.key, this.initial, this.draft});

  /// The template being edited, or `null` when creating a new one.
  final TransactionTemplateRow? initial;

  /// A quick-entry seed to pre-fill a new template from, or `null`.
  final TemplateDraft? draft;

  @override
  ConsumerState<TemplateFormScreen> createState() => _TemplateFormScreenState();
}

class _TemplateFormScreenState extends ConsumerState<TemplateFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  TransactionType _type = TransactionType.expense;
  String? _accountId;
  String? _destinationAccountId;
  String? _categoryId;

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
        title: Text(_isEditing ? 'Edit template' : 'New template'),
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
                    ? 'Enter a name for this template'
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
                  labelText: 'Amount (optional)',
                  hintText: 'Leave blank to fill in each time',
                  border: OutlineInputBorder(),
                ),
                validator: _validateAmount,
              ),
              const SizedBox(height: AppSpacing.lg),

              DropdownButtonFormField<String?>(
                initialValue: _accountId,
                decoration: const InputDecoration(
                  labelText: 'Account (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final a in activeAccounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (value) => setState(() {
                  _accountId = value;
                  if (_destinationAccountId == value) {
                    _destinationAccountId = null;
                  }
                }),
              ),

              if (_type == TransactionType.transfer) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String?>(
                  initialValue: _destinationAccountId,
                  decoration: const InputDecoration(
                    labelText: 'To (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final a in activeAccounts)
                      if (a.id != _accountId)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (value) =>
                      setState(() => _destinationAccountId = value),
                ),
              ],

              if (_type != TransactionType.transfer) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String?>(
                  initialValue: _categoryId,
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
                      : Text(_isEditing ? 'Save changes' : 'Add template'),
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
    if (input.isEmpty) return null;
    try {
      final minor = parseMinorUnits(input);
      if (minor <= 0) return 'Amount must be greater than zero';
    } on FormatException {
      return 'Enter a valid amount';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amountInput = _amountController.text.trim();
    final amountMinor = amountInput.isEmpty
        ? null
        : parseMinorUnits(amountInput);
    final name = _nameController.text.trim();
    final notes = _notesController.text.trim();

    setState(() => _saving = true);
    try {
      final controller = ref.read(templateControllerProvider);
      if (_isEditing) {
        await controller.update(
          id: widget.initial!.id,
          name: name,
          type: _type,
          amountMinor: amountMinor,
          accountId: _accountId,
          destinationAccountId: _destinationAccountId,
          categoryId: _categoryId,
          description: notes,
        );
      } else {
        await controller.create(
          name: name,
          type: _type,
          amountMinor: amountMinor,
          accountId: _accountId,
          destinationAccountId: _destinationAccountId,
          categoryId: _categoryId,
          description: notes,
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
