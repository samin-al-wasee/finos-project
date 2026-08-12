import 'quick_field.dart';

/// One top-level quick-entry command — what the first typed word selects.
///
/// Every write operation the app supports is reachable this way (a
/// deliberately broad, explicitly-authorized addition — see
/// docs/ARCHITECTURE.md, "quick entry"). Submitting a command never saves
/// anything itself: it opens the same screen (or dialog) that operation
/// already uses, pre-filled, for the user to review and save
/// (docs/ARCHITECTURE.md, "quick entry" — the same "review before saving"
/// shape as using a template or a saved filter).
class QuickCommandSpec {
  const QuickCommandSpec({
    required this.key,
    required this.label,
    required this.example,
    required this.fields,
  });

  /// The word that selects this command, matched case-insensitively against
  /// the first token (e.g. `'income'`).
  final String key;

  /// Shown in the top-level suggestion list, e.g. "Income".
  final String label;

  /// A short "field, field, field" hint shown next to [label].
  final String example;

  /// This command's slots, in the order typed tokens fill them.
  final List<QuickField> fields;
}

const _amount = QuickField(
  key: 'amount',
  label: 'Amount',
  kind: QuickFieldKind.amount,
);
const _amountOptional = QuickField(
  key: 'amount',
  label: 'Amount',
  kind: QuickFieldKind.amount,
  required: false,
);
const _date = QuickField(
  key: 'date',
  label: 'Date',
  kind: QuickFieldKind.date,
  required: false,
);
const _account = QuickField(
  key: 'account',
  label: 'Account',
  kind: QuickFieldKind.select,
  source: SuggestionSource.accounts,
);
const _accountOptional = QuickField(
  key: 'account',
  label: 'Account',
  kind: QuickFieldKind.select,
  source: SuggestionSource.accounts,
  required: false,
);
const _destinationAccount = QuickField(
  key: 'destinationAccount',
  label: 'To account',
  kind: QuickFieldKind.select,
  source: SuggestionSource.accounts,
);
const _descriptionOptional = QuickField(
  key: 'description',
  label: 'Note',
  kind: QuickFieldKind.text,
  required: false,
);

/// Every quick-entry command the bar supports.
///
/// Field order is chosen per command for what reads naturally when typed,
/// not forced into one universal shape — a loan repayment needs to know
/// *which* loan before an amount means anything, so `loan` comes first there
/// where every other money-movement command leads with `amount`.
const quickCommandSpecs = <QuickCommandSpec>[
  QuickCommandSpec(
    key: 'income',
    label: 'Income',
    example: 'amount, date, account, category',
    fields: [
      _amount,
      _date,
      _account,
      QuickField(
        key: 'category',
        label: 'Category',
        kind: QuickFieldKind.select,
        source: SuggestionSource.incomeCategories,
        required: false,
      ),
      _descriptionOptional,
    ],
  ),
  QuickCommandSpec(
    key: 'expense',
    label: 'Expense',
    example: 'amount, date, account, category',
    fields: [
      _amount,
      _date,
      _account,
      QuickField(
        key: 'category',
        label: 'Category',
        kind: QuickFieldKind.select,
        source: SuggestionSource.expenseCategories,
        required: false,
      ),
      _descriptionOptional,
    ],
  ),
  QuickCommandSpec(
    key: 'transfer',
    label: 'Transfer',
    example: 'amount, date, from account, to account',
    fields: [
      _amount,
      _date,
      _account,
      _destinationAccount,
      _descriptionOptional,
    ],
  ),
  QuickCommandSpec(
    key: 'lent',
    label: 'Lent',
    example: 'amount, date, who owes you, account',
    fields: [
      _amount,
      _date,
      QuickField(key: 'name', label: 'Who owes you', kind: QuickFieldKind.text),
      _accountOptional,
      _descriptionOptional,
    ],
  ),
  QuickCommandSpec(
    key: 'borrowed',
    label: 'Borrowed',
    example: 'amount, date, who you owe, account',
    fields: [
      _amount,
      _date,
      QuickField(key: 'name', label: 'Who you owe', kind: QuickFieldKind.text),
      _accountOptional,
      _descriptionOptional,
    ],
  ),
  QuickCommandSpec(
    key: 'repay',
    label: 'Repay a loan',
    example: 'loan, amount, date, account',
    fields: [
      QuickField(
        key: 'loan',
        label: 'Loan',
        kind: QuickFieldKind.select,
        source: SuggestionSource.outstandingLoans,
      ),
      _amountOptional,
      _date,
      _accountOptional,
    ],
  ),
  QuickCommandSpec(
    key: 'account',
    label: 'New account',
    example: 'name, type, opening balance',
    fields: [
      QuickField(key: 'name', label: 'Name', kind: QuickFieldKind.text),
      QuickField(
        key: 'type',
        label: 'Type',
        kind: QuickFieldKind.select,
        source: SuggestionSource.accountTypes,
        required: false,
      ),
      _amountOptional,
    ],
  ),
  QuickCommandSpec(
    key: 'category',
    label: 'New category',
    example: 'name, type',
    fields: [
      QuickField(key: 'name', label: 'Name', kind: QuickFieldKind.text),
      QuickField(
        key: 'type',
        label: 'Type',
        kind: QuickFieldKind.select,
        source: SuggestionSource.categoryTypes,
        required: false,
      ),
    ],
  ),
  QuickCommandSpec(
    key: 'budget',
    label: 'New budget',
    example: 'category, amount, period',
    fields: [
      QuickField(
        key: 'category',
        label: 'Category',
        kind: QuickFieldKind.select,
        source: SuggestionSource.expenseCategories,
      ),
      _amount,
      QuickField(
        key: 'period',
        label: 'Period',
        kind: QuickFieldKind.select,
        source: SuggestionSource.budgetPeriods,
        required: false,
      ),
    ],
  ),
  QuickCommandSpec(
    key: 'template',
    label: 'New template',
    example: 'name, type, amount, account, category',
    fields: [
      QuickField(key: 'name', label: 'Name', kind: QuickFieldKind.text),
      QuickField(
        key: 'type',
        label: 'Type',
        kind: QuickFieldKind.select,
        source: SuggestionSource.presetTransactionTypes,
        required: false,
      ),
      _amountOptional,
      _accountOptional,
      QuickField(
        key: 'category',
        label: 'Category',
        kind: QuickFieldKind.select,
        source: SuggestionSource.anyCategories,
        required: false,
      ),
      _descriptionOptional,
    ],
  ),
  QuickCommandSpec(
    key: 'recurring',
    label: 'New recurring rule',
    example: 'name, amount, account, frequency',
    fields: [
      QuickField(key: 'name', label: 'Name', kind: QuickFieldKind.text),
      _amount,
      _account,
      QuickField(
        key: 'frequency',
        label: 'Repeats',
        kind: QuickFieldKind.select,
        source: SuggestionSource.recurrenceFrequencies,
        required: false,
      ),
      _descriptionOptional,
    ],
  ),
];

/// Case-insensitive lookup by [QuickCommandSpec.key], or `null` if unmatched.
QuickCommandSpec? findQuickCommandSpec(String key) {
  final lower = key.toLowerCase();
  for (final spec in quickCommandSpecs) {
    if (spec.key == lower) return spec;
  }
  return null;
}
