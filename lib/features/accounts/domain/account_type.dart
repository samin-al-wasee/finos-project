import 'package:drift/drift.dart';

/// The kind of financial source an account represents (docs/DATA_MODEL.md §7).
enum AccountType { bank, mfs, creditCard, debitCard, cash, other }

/// Maps [AccountType] to its canonical uppercase storage value in the database
/// (`BANK`, `MFS`, `CREDIT_CARD`, ... — docs/DATA_MODEL.md §7).
class AccountTypeConverter extends TypeConverter<AccountType, String> {
  const AccountTypeConverter();

  static const Map<AccountType, String> _storage = {
    AccountType.bank: 'BANK',
    AccountType.mfs: 'MFS',
    AccountType.creditCard: 'CREDIT_CARD',
    AccountType.debitCard: 'DEBIT_CARD',
    AccountType.cash: 'CASH',
    AccountType.other: 'OTHER',
  };

  @override
  AccountType fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown AccountType storage value: $fromDb');
  }

  @override
  String toSql(AccountType value) => _storage[value]!;
}
