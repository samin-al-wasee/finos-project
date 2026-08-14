import 'package:drift/drift.dart';

/// Stored lifecycle state of a savings goal (docs/adr/011-savings-goals.md).
///
/// Only these two are persisted. Whether a goal has been *achieved* is
/// derived from its contributions/withdrawals at read time — see
/// `SavingsGoalProgress` — rather than stored, the same precedent
/// `LoanStatus`/`InvestmentStatus` set: reaching a derived milestone never
/// automatically changes the stored lifecycle state.
enum SavingsGoalStatus { active, archived }

/// Maps [SavingsGoalStatus] to its canonical uppercase storage value
/// (`ACTIVE`, `ARCHIVED`).
class SavingsGoalStatusConverter
    extends TypeConverter<SavingsGoalStatus, String> {
  const SavingsGoalStatusConverter();

  static const Map<SavingsGoalStatus, String> _storage = {
    SavingsGoalStatus.active: 'ACTIVE',
    SavingsGoalStatus.archived: 'ARCHIVED',
  };

  @override
  SavingsGoalStatus fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown SavingsGoalStatus storage value: $fromDb');
  }

  @override
  String toSql(SavingsGoalStatus value) => _storage[value]!;
}
