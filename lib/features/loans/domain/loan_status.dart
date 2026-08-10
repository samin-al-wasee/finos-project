import 'package:drift/drift.dart';

/// Stored lifecycle state of a loan (docs/DATA_MODEL.md §33, §39).
///
/// Only these two are persisted. Whether a loan is *paid* or *overdue* is derived
/// from its repayments and due date at read time — see `LoanProgress` — so it can
/// never disagree with the records behind it (ADR-004).
enum LoanStatus { active, archived }

/// Maps [LoanStatus] to its canonical uppercase storage value (`ACTIVE`,
/// `ARCHIVED`).
class LoanStatusConverter extends TypeConverter<LoanStatus, String> {
  const LoanStatusConverter();

  static const Map<LoanStatus, String> _storage = {
    LoanStatus.active: 'ACTIVE',
    LoanStatus.archived: 'ARCHIVED',
  };

  @override
  LoanStatus fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown LoanStatus storage value: $fromDb');
  }

  @override
  String toSql(LoanStatus value) => _storage[value]!;
}
