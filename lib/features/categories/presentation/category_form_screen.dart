import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/category_controller.dart';
import '../domain/category_type.dart';
import 'category_icon.dart';

/// Add/edit form for a single category.
///
/// When [initial] is provided the form pre-fills and saves via update;
/// otherwise it creates a new category. The type picker is hidden when editing
/// because a category's type is fixed at creation (docs/DATA_MODEL.md §18).
class CategoryFormScreen extends ConsumerStatefulWidget {
  const CategoryFormScreen({super.key, this.initial});

  /// The category being edited, or `null` when creating a new one.
  final CategoryRow? initial;

  @override
  ConsumerState<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late CategoryType _type;
  late String _icon;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _type = initial?.type ?? CategoryType.expense;
    _icon = initial?.icon ?? 'label';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(categoryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit category' : 'Add category'),
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
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Category name',
                  hintText: 'e.g. Groceries',
                  border: OutlineInputBorder(),
                ),
                validator: _validateName,
              ),
              if (!_isEditing) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<CategoryType>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Category type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final type in CategoryType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(categoryTypeLabel(type)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text('Icon', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              _IconPicker(
                selected: _icon,
                onChanged: (icon) {
                  setState(() => _icon = icon);
                },
              ),
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
                      : Text(_isEditing ? 'Save changes' : 'Add category'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter a category name';
    if (name.length > 40) return 'Name must be 40 characters or fewer';
    return null;
  }

  Future<void> _save(CategoryController controller) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final name = _nameController.text.trim();

    try {
      if (_isEditing) {
        await controller.update(
          id: widget.initial!.id,
          name: name,
          icon: _icon,
        );
      } else {
        await controller.create(name: name, type: _type, icon: _icon);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e, s) {
      debugPrint('[CategoryForm] save error: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the category: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// A wrap of tappable icon chips; the selected icon is highlighted.
class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final key in categoryIconKeys)
          InkWell(
            key: ValueKey('icon-$key'),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            onTap: () => onChanged(key),
            child: CircleAvatar(
              backgroundColor: key == selected
                  ? colors.primary
                  : colors.surfaceContainerHighest,
              child: Icon(
                categoryIcon(key),
                color: key == selected ? colors.onPrimary : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// User-facing label for a [CategoryType].
String categoryTypeLabel(CategoryType type) {
  switch (type) {
    case CategoryType.expense:
      return 'Expense';
    case CategoryType.income:
      return 'Income';
  }
}
