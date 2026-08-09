import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/category_status.dart';
import 'category_table.dart';

part 'category_dao.g.dart';

/// Data access object for categories (docs/DATA_MODEL.md §18–§21).
///
/// Mirrors the [AccountDao] pattern: streams, one-shot queries, CRUD, and
/// lifecycle status updates.
@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  /// Stream all categories (ordered by name), including archived ones.
  ///
  /// Archived categories are included so management screens can group them in
  /// an "Archived" section and allow restoring them (docs/DATA_MODEL.md §21).
  Stream<List<CategoryRow>> watchAll() {
    return (select(
      categories,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  }

  /// One-shot fetch all categories (ordered by name), including archived ones.
  Future<List<CategoryRow>> getAll() async {
    return (select(
      categories,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  /// Get a single category by ID. Returns `null` if not found.
  Future<CategoryRow?> getById(String id) {
    return (select(
      categories,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Persists a new category row.
  Future<void> insertOne(CategoriesCompanion entry) =>
      into(categories).insert(entry);

  /// Replaces the entire row for an existing category.
  ///
  /// `replace` derives the WHERE clause from the row's primary key, so no
  /// explicit condition is needed.
  Future<void> updateOne(CategoryRow row) => (update(categories)).replace(row);

  /// Transitions the lifecycle [status] of the category identified by [id].
  ///
  /// Throws [StateError] if no category with that [id] exists.
  Future<void> updateStatus(String id, CategoryStatus status) async {
    final category = await getById(id);
    if (category == null) throw StateError('Category not found: $id');
    await updateOne(
      category.copyWith(status: status, updatedAt: DateTime.now()),
    );
  }
}
