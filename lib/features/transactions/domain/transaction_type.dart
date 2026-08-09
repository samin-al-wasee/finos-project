import 'package:drift/drift.dart';

/// The kind of money movement a transaction records (docs/DATA_MODEL.md §13).
///
/// The amount is always stored as a positive integer in minor units; the
/// direction the money moves is derived from the type. Income increases an
/// account's balance, expense decreases it, and a transfer moves funds between
/// two accounts without changing the total.
enum TransactionType { income, expense, transfer }

/// Maps [TransactionType] to its canonical uppercase storage value in the
/// database (`INCOME`, `EXPENSE`, `TRANSFER` — docs/DATA_MODEL.md §13).
class TransactionTypeConverter extends TypeConverter<TransactionType, String> {
  const TransactionTypeConverter();

  static const Map<TransactionType, String> _storage = {
    TransactionType.income: 'INCOME',
    TransactionType.expense: 'EXPENSE',
    TransactionType.transfer: 'TRANSFER',
  };

  @override
  TransactionType fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown TransactionType storage value: $fromDb');
  }

  @override
  String toSql(TransactionType value) => _storage[value]!;
}
