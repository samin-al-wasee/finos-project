import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../categories/domain/category_status.dart';
import '../../categories/domain/category_type.dart';
import '../application/budget_controller.dart';
import '../domain/budget_period.dart';
import 'budget_labels.dart';

/// Add/edit form for a single budget (FR-04).
///
/// When [initial] is provided the form pre-fills and saves via update; otherwise
/// it creates a new budget. The category picker is hidden when editing because a
/// budget's category is fixed at creation — changing it would silently
/// reinterpret every past reading of the budget.
class BudgetFormScreen extends ConsumerStatefulWidget {
  const BudgetFormScreen({super.key, this.initial});

  /// The budget being edited, or `null` when creating a new one.
  final BudgetRow? initial;

  @override
  ConsumerState<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends ConsumerState<BudgetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  String? _categoryId;
  late BudgetPeriod _period;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;
  bool get _isCustom => _period == BudgetPeriod.custom;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _amountController = TextEditingController(
      text: initial == null ? '' : minorUnitsToInput(initial.amountMinor),
    );
    _categoryId = initial?.categoryId;
    _period = initial?.period ?? BudgetPeriod.monthly;
    _startDate = initial?.startDate ?? DateTime.now();
    _endDate = initial?.endDate;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(budgetControllerProvider);
    final colors = Theme.of(context).extension<FinosColors>()!;

    // Budgets cap spending, so only active expense categories are offered
    // (docs/DATA_MODEL.md §24).
    final categories = ref
        .watch(categoriesStreamProvider)
        .maybeWhen(
          data: (rows) => rows
              .where(
                (c) =>
                    c.status == CategoryStatus.active &&
                    c.type == CategoryType.expense,
              )
              .toList(),
          orElse: () => <CategoryRow>[],
        );

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit budget' : 'Add budget')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // ── Category ────────────────────────────────────────────────
              if (_isEditing)
                _ReadOnlyCategory(categoryId: widget.initial!.categoryId)
              else
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                  validator: (value) =>
                      value == null ? 'Choose a category' : null,
                ),

              // ── Limit ───────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _amountController,
                autofocus: !_isEditing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Limit',
                  hintText: 'e.g. 10000',
                  border: OutlineInputBorder(),
                ),
                validator: _validateAmount,
              ),

              // ── Period ──────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<BudgetPeriod>(
                initialValue: _period,
                decoration: const InputDecoration(
                  labelText: 'Period',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final period in BudgetPeriod.values)
                    DropdownMenuItem(
                      value: period,
                      child: Text(budgetPeriodLabel(period)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _period = value;
                    // A recurring period derives its window from the calendar,
                    // so any previously chosen end date no longer applies.
                    if (value != BudgetPeriod.custom) _endDate = null;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _isCustom
                    ? 'Spending is measured between the dates below.'
                    : '${budgetPeriodLabel(_period)} budgets reset every '
                          '${_resetNoun(_period)}.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.mutedText),
              ),

              // ── Dates ───────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_isCustom ? 'Start date' : 'Starts on'),
                trailing: Text(
                  formatDate(_startDate),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                onTap: _pickStartDate,
              ),
              if (_isCustom)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End date'),
                  trailing: Text(
                    _endDate == null ? 'Choose' : formatDate(_endDate!),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  onTap: _pickEndDate,
                ),

              // ── Save ────────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.xxl),
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
                      : Text(_isEditing ? 'Save changes' : 'Add budget'),
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
    if (input.isEmpty) return 'Enter a limit';
    try {
      if (parseMinorUnits(input) <= 0) {
        return 'Limit must be greater than zero';
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
      // Budgets are forward-looking, so a start date may be in the future.
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

  // ── Save ────────────────────────────────────────────────────────────────

  Future<void> _save(BudgetController controller) async {
    if (!_formKey.currentState!.validate()) return;
    if (_isCustom && _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an end date for this budget')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final amountMinor = parseMinorUnits(_amountController.text.trim());
      if (_isEditing) {
        await controller.update(
          id: widget.initial!.id,
          amountMinor: amountMinor,
          period: _period,
          startDate: _startDate,
          endDate: _endDate,
        );
      } else {
        await controller.create(
          categoryId: _categoryId!,
          amountMinor: amountMinor,
          period: _period,
          startDate: _startDate,
          endDate: _endDate,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Validation failures carry user-readable messages; nothing financial is
      // logged (AGENTS.md §15).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the budget: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Shows the fixed category of a budget being edited.
class _ReadOnlyCategory extends ConsumerWidget {
  const _ReadOnlyCategory({required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref
        .watch(categoriesStreamProvider)
        .maybeWhen(
          data: (rows) => rows
              .where((c) => c.id == categoryId)
              .map((c) => c.name)
              .firstOrNull,
          orElse: () => null,
        );

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Category',
        border: OutlineInputBorder(),
        helperText: 'A budget keeps the category it was created with',
      ),
      child: Text(name ?? '—'),
    );
  }
}

/// The noun used in "resets every …" for a recurring period.
String _resetNoun(BudgetPeriod period) {
  switch (period) {
    case BudgetPeriod.weekly:
      return 'week';
    case BudgetPeriod.monthly:
      return 'month';
    case BudgetPeriod.yearly:
      return 'year';
    case BudgetPeriod.custom:
      return 'period';
  }
}
