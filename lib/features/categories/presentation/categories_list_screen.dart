import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/category_origin.dart';
import '../domain/category_status.dart';
import '../domain/category_type.dart';
import 'category_icon.dart';
import 'category_form_screen.dart';

/// Category management screen (FR-03).
///
/// Watches the categories stream and groups active categories by type, with
/// archived categories collected below. A floating action button opens the
/// create form; per-tile menus expose edit/archive/restore.
class CategoriesListScreen extends ConsumerWidget {
  const CategoriesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        tooltip: 'Add category',
        child: const Icon(Icons.add),
      ),
      body: categories.when(
        data: (rows) => rows.isEmpty
            ? const EmptyState(
                icon: Icons.category_outlined,
                title: 'No categories yet',
                message: 'Add categories to organise your spending and income.',
              )
            : _CategoryList(rows: rows),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: error.toString(),
        ),
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xxxl),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }

  void _openForm(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CategoryFormScreen()));
  }
}

/// Groups [rows] into Expense/Income sections with archived categories at the
/// bottom.
class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.rows});

  final List<CategoryRow> rows;

  @override
  Widget build(BuildContext context) {
    final active = rows
        .where((r) => r.status == CategoryStatus.active)
        .toList();
    final archived = rows
        .where((r) => r.status == CategoryStatus.archived)
        .toList();
    final expenses = active
        .where((r) => r.type == CategoryType.expense)
        .toList();
    final incomes = active.where((r) => r.type == CategoryType.income).toList();

    final children = <Widget>[
      if (expenses.isNotEmpty) ...[
        const _SectionHeader(title: 'Expense'),
        for (final row in expenses) _CategoryTile(row: row),
      ],
      if (incomes.isNotEmpty) ...[
        const _SectionHeader(title: 'Income'),
        for (final row in incomes) _CategoryTile(row: row),
      ],
      if (archived.isNotEmpty) ...[
        const _SectionHeader(title: 'Archived'),
        for (final row in archived) _CategoryTile(row: row, archived: true),
      ],
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: children,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FinosColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: colors.mutedText),
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.row, this.archived = false});

  final CategoryRow row;
  final bool archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final system = row.origin == CategoryOrigin.system;

    return ListTile(
      leading: CircleAvatar(child: Icon(categoryIcon(row.icon))),
      title: Text(row.name),
      subtitle: system ? const Text('System') : null,
      trailing: PopupMenuButton<String>(
        onSelected: (value) => _handleMenu(context, ref, value),
        itemBuilder: (context) => [
          if (!system) const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (archived)
            const PopupMenuItem(value: 'restore', child: Text('Restore'))
          else
            const PopupMenuItem(value: 'archive', child: Text('Archive')),
        ],
      ),
      enabled: !archived,
      onTap: !system && !archived
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CategoryFormScreen(initial: row),
              ),
            )
          : null,
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final controller = ref.read(categoryControllerProvider);
    try {
      switch (value) {
        case 'edit':
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CategoryFormScreen(initial: row),
            ),
          );
        case 'archive':
          await controller.archive(row.id);
        case 'restore':
          await controller.restore(row.id);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the category')),
        );
      }
    }
  }
}
