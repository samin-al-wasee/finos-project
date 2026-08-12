import 'package:drift/drift.dart';

/// Lifecycle state of a recurring transaction rule.
///
/// Archiving stops generating due occurrences without losing the rule or the
/// transactions it already created — the same shape as budgets and categories
/// (docs/DATA_MODEL.md §39).
enum RecurringStatus { active, archived }

/// Maps [RecurringStatus] to its canonical uppercase storage value in the
/// database (`ACTIVE`, `ARCHIVED`).
class RecurringStatusConverter extends TypeConverter<RecurringStatus, String> {
  const RecurringStatusConverter();

  static const Map<RecurringStatus, String> _storage = {
    RecurringStatus.active: 'ACTIVE',
    RecurringStatus.archived: 'ARCHIVED',
  };

  @override
  RecurringStatus fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown RecurringStatus storage value: $fromDb');
  }

  @override
  String toSql(RecurringStatus value) => _storage[value]!;
}
