import '../../transactions/domain/transaction_type.dart';

/// A partial, unsaved set of pre-fill values for [TemplateFormScreen]'s
/// create flow.
class TemplateDraft {
  const TemplateDraft({
    this.name = '',
    this.type = TransactionType.expense,
    this.amountMinor,
    this.accountId,
    this.destinationAccountId,
    this.categoryId,
    this.description = '',
  });

  final String name;
  final TransactionType type;
  final int? amountMinor;
  final String? accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String description;
}
