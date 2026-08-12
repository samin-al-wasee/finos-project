/// How a [QuickField]'s value is entered and, where applicable, suggested.
enum QuickFieldKind {
  /// Free text, always manual — no suggestions.
  text,

  /// A decimal amount, always manual — no suggestions.
  amount,

  /// A calendar date. Manual entry (`today`, `2026-08-12`) is accepted, but
  /// `@` opens a native date picker rather than a filtered list.
  date,

  /// One value chosen from a live, filterable list sourced from [QuickField.source].
  select,
}

/// Where a [QuickFieldKind.select] field's candidates come from.
///
/// Resolving a source into actual candidates needs live app data (accounts,
/// categories, loans), so it happens in the presentation layer, which can
/// watch the relevant providers — this enum only names *which* list.
enum SuggestionSource {
  /// Not applicable — [QuickFieldKind.text]/[QuickFieldKind.amount]/
  /// [QuickFieldKind.date] fields carry this.
  none,

  /// The top-level command names themselves (docs/ROADMAP.md quick-entry note).
  topLevelCommands,

  /// Active financial accounts.
  accounts,

  /// Active income categories.
  incomeCategories,

  /// Active expense categories.
  expenseCategories,

  /// Active categories of either type — used where a command's own type
  /// isn't fixed yet (e.g. a template's category can be income or expense).
  anyCategories,

  /// Loans that still have something outstanding — repayment targets.
  outstandingLoans,

  /// The fixed [AccountType] values.
  accountTypes,

  /// The fixed [BudgetPeriod] values.
  budgetPeriods,

  /// The fixed [CategoryType] values.
  categoryTypes,

  /// The transaction types a preset (template/recurring rule) may hold —
  /// income, expense, or transfer.
  presetTransactionTypes,

  /// The fixed [RecurrenceFrequency] values.
  recurrenceFrequencies,
}

/// One positional slot in a [QuickCommandSpec] — e.g. "amount" or "account".
///
/// Fields are matched to typed tokens purely by position within a command
/// (see quick_command_parser.dart), not by name or prefix.
class QuickField {
  const QuickField({
    required this.key,
    required this.label,
    required this.kind,
    this.source = SuggestionSource.none,
    this.required = true,
  });

  /// Stable identifier used as the key in a parsed command's value map, e.g.
  /// `'amount'`, `'account'`.
  final String key;

  /// Shown in the suggestion panel while this slot is active, e.g. "Amount".
  final String label;

  final QuickFieldKind kind;

  /// Only meaningful when [kind] is [QuickFieldKind.select].
  final SuggestionSource source;

  /// Whether [quick_command_resolver.dart] rejects the command when this
  /// field is left blank.
  final bool required;
}
