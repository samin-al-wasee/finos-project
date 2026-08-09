import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../data/category_dao.dart';
import '../domain/category_origin.dart';
import '../domain/category_status.dart';
import '../domain/category_type.dart';

/// Application-service for the category lifecycle.
///
/// Sits between the presentation layer and the data layer: it owns business
/// rules (ID generation, which fields an update may change, system-category
/// protections) and keeps screens free of database and domain concerns.
class CategoryController {
  CategoryController(this._dao);

  final CategoryDao _dao;

  /// Creates a new user category with a fresh ULID.
  ///
  /// Returns the generated ID so callers can navigate to the new category
  /// if needed.
  Future<String> create({
    required String name,
    required CategoryType type,
    String icon = 'label',
  }) async {
    final id = generateId();
    await _dao.insertOne(
      CategoriesCompanion.insert(
        id: id,
        name: name,
        type: type,
        origin: const Value(CategoryOrigin.user),
        icon: Value(icon),
      ),
    );
    return id;
  }

  /// Updates the name and/or icon of a category.
  ///
  /// Throws [StateError] if the category doesn't exist or is a system category
  /// (system categories cannot be renamed).
  Future<void> update({
    required String id,
    required String name,
    required String icon,
  }) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Category not found: $id');
    if (row.origin == CategoryOrigin.system) {
      throw StateError('System categories cannot be renamed');
    }
    await _dao.updateOne(
      row.copyWith(name: name, icon: icon, updatedAt: DateTime.now()),
    );
  }

  /// Archives a category (soft-delete).
  ///
  /// Both system and user categories can be archived.
  /// Throws [StateError] if the category doesn't exist.
  Future<void> archive(String id) =>
      _dao.updateStatus(id, CategoryStatus.archived);

  /// Re-activates a previously archived category.
  ///
  /// Throws [StateError] if the category doesn't exist.
  Future<void> restore(String id) =>
      _dao.updateStatus(id, CategoryStatus.active);

  /// Returns the category identified by [id], or `null` if not found.
  Future<CategoryRow?> getById(String id) => _dao.getById(id);
}
