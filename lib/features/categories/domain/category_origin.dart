import 'package:drift/drift.dart';

/// Whether a category is provided by FinOS or created by the user
/// (docs/DATA_MODEL.md §20).
enum CategoryOrigin { system, user }

/// Maps [CategoryOrigin] to its canonical uppercase storage value in the
/// database (`SYSTEM`, `USER` — docs/DATA_MODEL.md §20).
class CategoryOriginConverter extends TypeConverter<CategoryOrigin, String> {
  const CategoryOriginConverter();

  static const Map<CategoryOrigin, String> _storage = {
    CategoryOrigin.system: 'SYSTEM',
    CategoryOrigin.user: 'USER',
  };

  @override
  CategoryOrigin fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown CategoryOrigin storage value: $fromDb');
  }

  @override
  String toSql(CategoryOrigin value) => _storage[value]!;
}
