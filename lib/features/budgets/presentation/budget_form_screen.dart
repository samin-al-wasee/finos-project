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
import '../domain/budget_draft.dart';
import '../domain/budget_period.dart';
import '../domain/budget_scope.dart';
import 'budget_labels.dart';

/// Add/edit form for a single budget (FR-04).
///
/// When [initial] is provided the form pre-fills and saves via update; otherwise
/// it creates a new budget. The scope-type selector and category picker are
/// hidden when editing because a budget's scope is fixed at creation —
/// changing it would silently reinterpret every past reading of the budget
/// (docs/adr/007-flexible-budget-scope.md, generalising the same rule that
/// already fixed a `SINGLE_CATEGORY` budget's category). [draft] does the same
/// for quick entry (docs/ARCHITECTURE.md, "quick entry") — a one-off, unsaved
/// seed, ignored when [initial] is set. Quick entry has no natural grammar for
/// "multiple categories," so a quick-entry-created budget is always
/// [BudgetScopeType.singleCategory].
class BudgetFormScreen extends ConsumerStatefulWidget {
  const BudgetFormScreen({super.key, this.initial, this.draft});

  /// The budget being edited, or `null` when creating a new one.
  final BudgetRow? initial;

  /// A quick-entry seed to pre-fill a new budget from, or `null`.
  final BudgetDraft? draft;

  @override
  ConsumerState<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends ConsumerState<BudgetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late BudgetScopeType _scopeType;
  String? _categoryId;
  final Set<String> _categoryIds = {};
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
    final draft = initial == null ? widget.draft : null;

    final presetAmountMinor = initial?.amountMinor ?? draft?.amountMinor;
    _amountController = TextEditingController(
      text: presetAmountMinor == null
          ? ''
          : minorUnitsToInput(presetAmountMinor),
    );
    _scopeType = initial?.scopeType ?? BudgetScopeType.singleCategory;
    _categoryId = initial?.categoryId ?? draft?.categoryId;
    _period = initial?.period ?? draft?.period ?? BudgetPeriod.monthly;
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
              // ── Scope ───────────────────────────────────────────────────
              if (_isEditing)
                _ReadOnlyScope(budgetId: widget.initial!.id)
              else ...[
                DropdownButtonFormField<BudgetScopeType>(
                  initialValue: _scopeType,
                  decoration: const InputDecoration(
                    labelText: 'Scope',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final type in BudgetScopeType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(budgetScopeTypeLabel(type)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _scopeType = value;
                      if (value != BudgetScopeType.singleCategory) {
                        _categoryId = null;
                      }
                      if (value != BudgetScopeType.multiCategory) {
                        _categoryIds.clear();
                      }
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                _CategoryInput(
                  scopeType: _scopeType,
                  categories: categories,
                  categoryId: _categoryId,
                  categoryIds: _categoryIds,
                  onCategoryChanged: (value) =>
                      setState(() => _categoryId = value),
                  onCategoryIdsChanged: () => setState(() {}),
                ),
              ],

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

  BudgetScope _buildScope() {
    switch (_scopeType) {
      case BudgetScopeType.singleCategory:
        return SingleCategoryScope(_categoryId!);
      case BudgetScopeType.multiCategory:
        return MultiCategoryScope(_categoryIds);
      case BudgetScopeType.uncategorized:
        return const UncategorizedScope();
      case BudgetScopeType.wholeAccount:
        return const WholeAccountScope();
    }
  }

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
          scope: _buildScope(),
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

/// The category input, conditional on [scopeType] (docs/adr/007-flexible-budget-scope.md):
/// a single dropdown, a multi-select checklist (≥ 2 required), or explanatory
/// text for the two category-less scopes.
class _CategoryInput extends StatelessWidget {
  const _CategoryInput({
    required this.scopeType,
    required this.categories,
    required this.categoryId,
    required this.categoryIds,
    required this.onCategoryChanged,
    required this.onCategoryIdsChanged,
  });

  final BudgetScopeType scopeType;
  final List<CategoryRow> categories;
  final String? categoryId;
  final Set<String> categoryIds;
  final ValueChanged<String?> onCategoryChanged;

  /// Called after [categoryIds] is mutated in place, so the parent can rebuild.
  final VoidCallback onCategoryIdsChanged;

  @override
  Widget build(BuildContext context) {
    switch (scopeType) {
      case BudgetScopeType.singleCategory:
        return DropdownButtonFormField<String>(
          initialValue: categoryId,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final category in categories)
              DropdownMenuItem(value: category.id, child: Text(category.name)),
          ],
          onChanged: onCategoryChanged,
          validator: (value) => value == null ? 'Choose a category' : null,
        );
      case BudgetScopeType.multiCategory:
        return FormField<Set<String>>(
          initialValue: categoryIds,
          validator: (value) => (value == null || value.length < 2)
              ? 'Choose at least 2 categories'
              : null,
          builder: (field) {
            return InputDecorator(
              decoration: InputDecoration(
                labelText: 'Categories',
                border: const OutlineInputBorder(),
                errorText: field.errorText,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final category in categories)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(category.name),
                      value: categoryIds.contains(category.id),
                      onChanged: (checked) {
                        if (checked == true) {
                          categoryIds.add(category.id);
                        } else {
                          categoryIds.remove(category.id);
                        }
                        field.didChange(categoryIds);
                        onCategoryIdsChanged();
                      },
                    ),
                ],
              ),
            );
          },
        );
      case BudgetScopeType.uncategorized:
        return const Text('This budget covers every expense with no category.');
      case BudgetScopeType.wholeAccount:
        return const Text(
          'This budget covers every expense, in every category.',
        );
    }
  }
}

/// Shows the fixed scope of a budget being edited.
class _ReadOnlyScope extends ConsumerWidget {
  const _ReadOnlyScope({required this.budgetId});

  final String budgetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref
        .watch(budgetProgressProvider)
        .maybeWhen(
          data: (rows) {
            for (final row in rows) {
              if (row.budget.id == budgetId) return budgetScopeLabel(row);
            }
            return null;
          },
          orElse: () => null,
        );

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Scope',
        border: OutlineInputBorder(),
        helperText: 'A budget keeps the scope it was created with',
      ),
      child: Text(label ?? '—'),
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
