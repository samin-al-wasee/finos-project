import '../../transactions/domain/transaction_type.dart';
import 'recurrence_frequency.dart';

/// A partial, unsaved set of pre-fill values for
/// [RecurringTransactionFormScreen]'s create flow.
class RecurringDraft {
  const RecurringDraft({
    this.name = '',
    this.type = TransactionType.expense,
    this.amountMinor,
    this.accountId,
    this.destinationAccountId,
    this.categoryId,
    this.frequency = RecurrenceFrequency.monthly,
    this.startDate,
    this.description = '',
  });

  final String name;
  final TransactionType type;
  final int? amountMinor;
  final String? accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final RecurrenceFrequency frequency;

  /// Defaults to today when `null`, same as a blank new rule.
  final DateTime? startDate;
  final String description;
}
