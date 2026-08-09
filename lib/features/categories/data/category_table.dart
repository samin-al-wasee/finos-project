import 'package:drift/drift.dart';

import '../domain/category_origin.dart';
import '../domain/category_status.dart';
import '../domain/category_type.dart';

/// Drift table for transaction categories (docs/DATA_MODEL.md §18–§21).
///
/// `type` ties a category to the transaction types it is valid for; `origin`
/// distinguishes FinOS-provided categories from user-created ones. Built-in
/// (system) categories must not be renamed or destructively deleted.
@DataClassName('CategoryRow')
class Categories extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  /// Built-ins use deterministic slugs (e.g. `cat-food`) so seeding is stable.
  TextColumn get id => text()();

  /// User-facing category name.
  TextColumn get name => text()();

  /// Transaction type this category is valid for — docs/DATA_MODEL.md §19.
  TextColumn get type => text().map(const CategoryTypeConverter())();

  /// Built-in (SYSTEM) vs user-created (USER) — docs/DATA_MODEL.md §20.
  TextColumn get origin => text()
      .map(const CategoryOriginConverter())
      .withDefault(const Constant('USER'))();

  /// Material icon key; resolved to an [IconData] in the presentation layer.
  TextColumn get icon => text().withDefault(const Constant('label'))();

  /// Lifecycle state — docs/DATA_MODEL.md §21.
  TextColumn get status => text()
      .map(const CategoryStatusConverter())
      .withDefault(const Constant('ACTIVE'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
