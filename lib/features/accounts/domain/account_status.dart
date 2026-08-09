import 'package:drift/drift.dart';

/// Lifecycle state of a financial account (docs/DATA_MODEL.md §8).
enum AccountStatus { active, archived }

/// Maps [AccountStatus] to its canonical uppercase storage value in the
/// database (`ACTIVE`, `ARCHIVED` — docs/DATA_MODEL.md §8).
class AccountStatusConverter extends TypeConverter<AccountStatus, String> {
  const AccountStatusConverter();

  static const Map<AccountStatus, String> _storage = {
    AccountStatus.active: 'ACTIVE',
    AccountStatus.archived: 'ARCHIVED',
  };

  @override
  AccountStatus fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown AccountStatus storage value: $fromDb');
  }

  @override
  String toSql(AccountStatus value) => _storage[value]!;
}
