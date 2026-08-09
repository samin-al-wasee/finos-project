import 'package:drift/drift.dart';

/// Lifecycle state of a category (docs/DATA_MODEL.md §20–§21).
enum CategoryStatus { active, archived }

/// Maps [CategoryStatus] to its canonical uppercase storage value in the
/// database (`ACTIVE`, `ARCHIVED`).
class CategoryStatusConverter extends TypeConverter<CategoryStatus, String> {
  const CategoryStatusConverter();

  static const Map<CategoryStatus, String> _storage = {
    CategoryStatus.active: 'ACTIVE',
    CategoryStatus.archived: 'ARCHIVED',
  };

  @override
  CategoryStatus fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown CategoryStatus storage value: $fromDb');
  }

  @override
  String toSql(CategoryStatus value) => _storage[value]!;
}
