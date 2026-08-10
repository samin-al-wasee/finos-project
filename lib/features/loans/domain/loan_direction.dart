import 'package:drift/drift.dart';

import '../../transactions/domain/transaction_type.dart';

/// Which way a loan runs (docs/DATA_MODEL.md §29–§31).
///
/// The distinction must never be lost: [lent] is a receivable the user expects
/// back, [borrowed] is a liability the user still owes (AGENTS.md §10).
enum LoanDirection { lent, borrowed }

/// Maps [LoanDirection] to its canonical uppercase storage value (`LENT`,
/// `BORROWED`).
class LoanDirectionConverter extends TypeConverter<LoanDirection, String> {
  const LoanDirectionConverter();

  static const Map<LoanDirection, String> _storage = {
    LoanDirection.lent: 'LENT',
    LoanDirection.borrowed: 'BORROWED',
  };

  @override
  LoanDirection fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown LoanDirection storage value: $fromDb');
  }

  @override
  String toSql(LoanDirection value) => _storage[value]!;
}

/// The transaction type recording this loan's **origination** — the movement when
/// the loan is first made (ADR-004).
///
/// Lending hands money out; borrowing takes money in.
TransactionType originationTypeFor(LoanDirection direction) {
  switch (direction) {
    case LoanDirection.lent:
      return TransactionType.loanPayment;
    case LoanDirection.borrowed:
      return TransactionType.loanReceipt;
  }
}

/// The transaction type recording a **repayment** against this loan (ADR-004).
///
/// Always the opposite side from origination: money comes back in on a loan the
/// user made, and goes back out on one they took. Because the two sides are
/// always opposite, a loan's repayments are identifiable by type alone — no extra
/// flag is needed to tell them apart from the origination movement.
TransactionType repaymentTypeFor(LoanDirection direction) {
  switch (direction) {
    case LoanDirection.lent:
      return TransactionType.loanReceipt;
    case LoanDirection.borrowed:
      return TransactionType.loanPayment;
  }
}
