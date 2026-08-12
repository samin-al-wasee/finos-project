import 'transaction_type.dart';

/// A partial, unsaved set of pre-fill values for [TransactionFormScreen].
///
/// Distinct from [TransactionTemplateRow]: a template is a persisted preset,
/// while a draft is a one-off, in-memory seed — quick entry's use case. Both
/// pre-fill the same screen, via separate constructor parameters, so neither
/// concept has to fake the other's shape.
class TransactionDraft {
  const TransactionDraft({
    required this.type,
    this.amountMinor,
    this.accountId,
    this.destinationAccountId,
    this.categoryId,
    this.description = '',
    this.date,
  });

  final TransactionType type;
  final int? amountMinor;
  final String? accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String description;

  /// Defaults to today when `null`, same as a blank new transaction.
  final DateTime? date;
}
