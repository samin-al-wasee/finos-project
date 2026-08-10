import 'package:drift/drift.dart';

/// Lifecycle state of a budget (docs/DATA_MODEL.md §22, §39).
///
/// This is the stored lifecycle only. How a budget is *doing* against its limit
/// (under limit / near limit / exceeded) is derived from transactions at read
/// time and is never persisted — see `BudgetHealth` (docs/DATA_MODEL.md §25).
enum BudgetStatus { active, archived }

/// Maps [BudgetStatus] to its canonical uppercase storage value in the database
/// (`ACTIVE`, `ARCHIVED`).
class BudgetStatusConverter extends TypeConverter<BudgetStatus, String> {
  const BudgetStatusConverter();

  static const Map<BudgetStatus, String> _storage = {
    BudgetStatus.active: 'ACTIVE',
    BudgetStatus.archived: 'ARCHIVED',
  };

  @override
  BudgetStatus fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown BudgetStatus storage value: $fromDb');
  }

  @override
  String toSql(BudgetStatus value) => _storage[value]!;
}
