import '../../accounts/domain/account_type.dart';
import '../../budgets/domain/budget_period.dart';
import '../../categories/domain/category_type.dart';
import '../../recurring/domain/recurrence_frequency.dart';
import '../../transactions/domain/transaction_type.dart';

/// Label maps for the fixed-value [SuggestionSource]s.
///
/// Kept local to quick entry rather than imported from each feature's own
/// (presentation-layer) label helper, the same way every list screen in this
/// app already keeps its own small type-label map rather than sharing one
/// centrally (e.g. `transactions_list_screen.dart`'s `_typeLabel`).
const Map<AccountType, String> quickAccountTypeLabels = {
  AccountType.bank: 'Bank',
  AccountType.mfs: 'Mobile financial service',
  AccountType.creditCard: 'Credit card',
  AccountType.debitCard: 'Debit card',
  AccountType.cash: 'Cash',
  AccountType.other: 'Other',
};

const Map<CategoryType, String> quickCategoryTypeLabels = {
  CategoryType.expense: 'Expense',
  CategoryType.income: 'Income',
};

const Map<BudgetPeriod, String> quickBudgetPeriodLabels = {
  BudgetPeriod.weekly: 'Weekly',
  BudgetPeriod.monthly: 'Monthly',
  BudgetPeriod.yearly: 'Yearly',
  BudgetPeriod.custom: 'Custom',
};

const Map<RecurrenceFrequency, String> quickRecurrenceFrequencyLabels = {
  RecurrenceFrequency.daily: 'Daily',
  RecurrenceFrequency.weekly: 'Weekly',
  RecurrenceFrequency.monthly: 'Monthly',
  RecurrenceFrequency.yearly: 'Yearly',
};

/// The transaction types a preset (template/recurring rule) may hold.
const Map<TransactionType, String> quickPresetTransactionTypeLabels = {
  TransactionType.income: 'Income',
  TransactionType.expense: 'Expense',
  TransactionType.transfer: 'Transfer',
};

/// Case-insensitive reverse lookup: label text -> enum value, or `null` if
/// [raw] matches nothing in [labels].
T? matchQuickStaticOption<T>(String? raw, Map<T, String> labels) {
  if (raw == null || raw.trim().isEmpty) return null;
  final needle = raw.trim().toLowerCase();
  for (final entry in labels.entries) {
    if (entry.value.toLowerCase() == needle) return entry.key;
  }
  return null;
}
