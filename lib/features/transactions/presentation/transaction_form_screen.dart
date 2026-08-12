import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../accounts/domain/account_status.dart';
import '../../categories/domain/category_status.dart';
import '../../categories/domain/category_type.dart';
import '../../categories/presentation/categories_list_screen.dart';
import '../application/transaction_controller.dart';
import '../domain/transaction_type.dart';

/// Add/edit form for a single transaction (docs/UI_DESIGN.md §10–§13).
///
/// When [initial] is provided the form pre-fills and saves via update;
/// otherwise it creates a new transaction. The same widget powers both flows.
///
/// [template] pre-fills a *new* transaction from a saved preset
/// (docs/ROADMAP.md §8.2) — [initial] and [template] are mutually exclusive;
/// editing always takes precedence if somehow both are given. Using a
/// template never saves anything by itself: the user still reviews and taps
/// Save like any other new transaction, and today's date is always used
/// rather than whatever date the template might imply.
///
/// The amount field is visually dominant; account and category are chosen from
/// dropdowns populated by the reactive stream providers. For transfers the
/// category field is hidden and a destination account selector appears instead.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.initial, this.template});

  /// The transaction being edited, or `null` when creating a new one.
  final TransactionRow? initial;

  /// A saved preset to pre-fill a new transaction from, or `null`.
  final TransactionTemplateRow? template;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();

  /// Amount in major units (e.g. "500" for ৳500.00).
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  TransactionType _type = TransactionType.expense;
  String _accountId = '';
  String? _destinationAccountId;
  String? _categoryId;
  DateTime _date = DateTime.now();

  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final template = initial == null ? widget.template : null;

    final presetAmountMinor = initial?.amountMinor ?? template?.amountMinor;
    _amountController = TextEditingController(
      text: presetAmountMinor == null
          ? ''
          : minorUnitsToInput(presetAmountMinor),
    );
    _notesController = TextEditingController(
      text: initial?.description ?? template?.description ?? '',
    );
    _type = initial?.type ?? template?.type ?? TransactionType.expense;
    _accountId = initial?.accountId ?? template?.accountId ?? '';
    _destinationAccountId =
        initial?.destinationAccountId ?? template?.destinationAccountId;
    _categoryId = initial?.categoryId ?? template?.categoryId;
    // A template never pre-fills the date — it presets what the transaction
    // is, not when it happened.
    _date = initial?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(transactionControllerProvider);
    final accounts = ref.watch(accountsStreamProvider);
    final categories = ref.watch(categoriesStreamProvider);

    final accountRows = accounts.valueOrNull ?? [];
    final activeAccounts = accountRows
        .where((a) => a.status == AccountStatus.active)
        .toList();
    final categoryRows = categories.valueOrNull ?? [];
    final activeCategories = categoryRows
        .where((c) => c.status == CategoryStatus.active)
        .toList();

    // Categories compatible with the selected type.
    final filteredCategories = activeCategories.where((c) {
      if (_type == TransactionType.transfer) return false;
      return c.type ==
          (_type == TransactionType.income
              ? CategoryType.income
              : CategoryType.expense);
    }).toList();

    // Auto-select first account when creating and the list just populated.
    if (_accountId.isEmpty && activeAccounts.length == 1 && !_isEditing) {
      _accountId = activeAccounts.first.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit transaction' : 'Add transaction'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // ── Amount (dominant) ───────────────────────────────────────
              TextFormField(
                controller: _amountController,
                autofocus: !_isEditing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText:
                      '${currencySymbol(activeAccounts.isNotEmpty ? activeAccounts.first.currency : 'BDT')} ',
                  border: const OutlineInputBorder(),
                  hintText: '0.00',
                ),
                validator: _validateAmount,
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Type selector ───────────────────────────────────────────
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
                    // Clear category when switching to transfer.
                    if (_type == TransactionType.transfer) {
                      _categoryId = null;
                    }
                  });
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Account ("From") ────────────────────────────────────────
              DropdownButtonFormField<String>(
                initialValue:
                    _accountId.isNotEmpty &&
                        activeAccounts.any((a) => a.id == _accountId)
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
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _accountId = value;
                      // Reset destination if it's the same as the new source.
                      if (_destinationAccountId == value) {
                        _destinationAccountId = null;
                      }
                    });
                  }
                },
                validator: (v) => v == null ? 'Select an account' : null,
              ),

              // ── Destination ("To") — transfers only ─────────────────────
              if (_type == TransactionType.transfer) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _destinationAccountId,
                  decoration: const InputDecoration(
                    labelText: 'To',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final a in activeAccounts)
                      if (a.id != _accountId)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _destinationAccountId = value);
                    }
                  },
                  validator: (v) => v == null ? 'Select a destination' : null,
                ),
              ],

              // ── Category — income/expense only ──────────────────────────
              if (_type != TransactionType.transfer) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: InputDecoration(
                    labelText: 'Category (optional)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Manage categories',
                      icon: const Icon(Icons.category_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CategoriesListScreen(),
                        ),
                      ),
                    ),
                  ),
                  items: [
                    for (final c in filteredCategories)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (value) {
                    setState(() => _categoryId = value);
                  },
                ),
              ],

              // ── Date ────────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.lg),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                trailing: Text(
                  _formatDateShort(_date),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                onTap: _pickDate,
              ),

              // ── Notes ───────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.sm),
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

              // ── Save ────────────────────────────────────────────────────
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
                      : Text(_isEditing ? 'Save changes' : 'Add transaction'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Validation ──────────────────────────────────────────────────────────

  String? _validateAmount(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter an amount';
    try {
      final minor = parseMinorUnits(input);
      if (minor <= 0) return 'Amount must be greater than zero';
    } on FormatException {
      return 'Enter a valid amount';
    }
    return null;
  }

  // ── Date picker ─────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  String _formatDateShort(DateTime date) {
    final local = date.toLocal();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  // ── Save ────────────────────────────────────────────────────────────────

  Future<void> _save(TransactionController controller) async {
    if (!_formKey.currentState!.validate()) return;

    final amountInput = _amountController.text.trim();
    final amountMinor = parseMinorUnits(amountInput);

    setState(() => _saving = true);
    final notes = _notesController.text.trim();

    try {
      if (_isEditing) {
        await controller.update(
          id: widget.initial!.id,
          type: _type,
          amountMinor: amountMinor,
          accountId: _accountId,
          destinationAccountId: _type == TransactionType.transfer
              ? _destinationAccountId
              : null,
          categoryId: _type != TransactionType.transfer ? _categoryId : null,
          date: _date,
          description: notes,
        );
      } else {
        await controller.create(
          type: _type,
          amountMinor: amountMinor,
          accountId: _accountId,
          destinationAccountId: _type == TransactionType.transfer
              ? _destinationAccountId
              : null,
          categoryId: _type != TransactionType.transfer ? _categoryId : null,
          date: _date,
          description: notes,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e, s) {
      debugPrint('[TransactionForm] save error: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the transaction: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
