import 'package:drift/drift.dart';

/// Which transaction types a category is valid for (docs/DATA_MODEL.md §19).
enum CategoryType { expense, income }

/// Maps [CategoryType] to its canonical uppercase storage value in the database
/// (`EXPENSE`, `INCOME` — docs/DATA_MODEL.md §19).
class CategoryTypeConverter extends TypeConverter<CategoryType, String> {
  const CategoryTypeConverter();

  static const Map<CategoryType, String> _storage = {
    CategoryType.expense: 'EXPENSE',
    CategoryType.income: 'INCOME',
  };

  @override
  CategoryType fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown CategoryType storage value: $fromDb');
  }

  @override
  String toSql(CategoryType value) => _storage[value]!;
}
