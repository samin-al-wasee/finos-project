import 'package:drift/drift.dart';

/// Stored lifecycle state of an investment (docs/adr/009-investment-accounting.md).
///
/// Only these two are persisted. Whether an investment has *matured* is derived
/// from its maturity date at read time — see `InvestmentProgress` — rather than
/// stored, the same precedent `LoanStatus` sets for a loan's paid/overdue
/// standing (ADR-004). This deliberately avoids a stored `MATURED` state: with
/// nothing to un-set, correcting a mistaken maturity-payout confirmation is
/// just deleting the transaction, never undoing a status transition.
enum InvestmentStatus { active, archived }

/// Maps [InvestmentStatus] to its canonical uppercase storage value (`ACTIVE`,
/// `ARCHIVED`).
class InvestmentStatusConverter
    extends TypeConverter<InvestmentStatus, String> {
  const InvestmentStatusConverter();

  static const Map<InvestmentStatus, String> _storage = {
    InvestmentStatus.active: 'ACTIVE',
    InvestmentStatus.archived: 'ARCHIVED',
  };

  @override
  InvestmentStatus fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown InvestmentStatus storage value: $fromDb');
  }

  @override
  String toSql(InvestmentStatus value) => _storage[value]!;
}
