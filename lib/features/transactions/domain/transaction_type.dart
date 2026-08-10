import 'package:drift/drift.dart';

/// The kind of money movement a transaction records (docs/DATA_MODEL.md §13).
///
/// The amount is always stored as a positive integer in minor units; the
/// direction the money moves is derived from the type. Income increases an
/// account's balance, expense decreases it, and a transfer moves funds between
/// two accounts without changing the total.
///
/// [loanReceipt] and [loanPayment] record cash moving because of a loan — either
/// its origination or a repayment (ADR-004). Direction is intrinsic to the type
/// so balance queries never need to join to the loan: a receipt adds to the
/// account, a payment subtracts. Like transfers, they are balance-sheet movements
/// and never count as income or expense.
enum TransactionType { income, expense, transfer, loanReceipt, loanPayment }

/// Maps [TransactionType] to its canonical uppercase storage value in the
/// database (`INCOME`, `EXPENSE`, `TRANSFER`, `LOAN_RECEIPT`, `LOAN_PAYMENT` —
/// docs/DATA_MODEL.md §13).
class TransactionTypeConverter extends TypeConverter<TransactionType, String> {
  const TransactionTypeConverter();

  static const Map<TransactionType, String> _storage = {
    TransactionType.income: 'INCOME',
    TransactionType.expense: 'EXPENSE',
    TransactionType.transfer: 'TRANSFER',
    TransactionType.loanReceipt: 'LOAN_RECEIPT',
    TransactionType.loanPayment: 'LOAN_PAYMENT',
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

/// The types a user may create or edit directly.
///
/// Loan movements are deliberately excluded: they are created and removed only
/// through the loan feature, because editing one by hand would let a loan's
/// outstanding balance diverge from the transactions it is derived from
/// (ADR-004).
const userCreatableTransactionTypes = [
  TransactionType.income,
  TransactionType.expense,
  TransactionType.transfer,
];

/// Whether [type] records a loan movement rather than ordinary activity.
bool isLoanTransaction(TransactionType type) =>
    type == TransactionType.loanReceipt || type == TransactionType.loanPayment;
