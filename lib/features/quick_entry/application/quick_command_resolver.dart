import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../accounts/domain/account_draft.dart';
import '../../accounts/domain/account_type.dart';
import '../../budgets/domain/budget_draft.dart';
import '../../budgets/domain/budget_period.dart';
import '../../categories/domain/category_draft.dart';
import '../../categories/domain/category_type.dart';
import '../../loans/domain/loan_direction.dart';
import '../../loans/domain/loan_draft.dart';
import '../../loans/domain/loan_progress.dart';
import '../../recurring/domain/recurrence_frequency.dart';
import '../../recurring/domain/recurring_draft.dart';
import '../../templates/domain/template_draft.dart';
import '../../transactions/domain/transaction_draft.dart';
import '../../transactions/domain/transaction_type.dart';
import '../domain/quick_command_spec.dart';
import '../domain/quick_static_options.dart';

/// What a resolved quick-entry command should do next.
///
/// Always "open the existing screen or dialog for this operation, pre-filled"
/// — never a direct save (docs/ARCHITECTURE.md, "quick entry"). The widget
/// that calls [resolveQuickCommand] switches on the concrete type to decide
/// which screen/dialog to open; this file knows nothing about navigation.
sealed class QuickDispatch {
  const QuickDispatch();
}

class DispatchTransactionForm extends QuickDispatch {
  const DispatchTransactionForm(this.draft);
  final TransactionDraft draft;
}

class DispatchLoanForm extends QuickDispatch {
  const DispatchLoanForm(this.draft);
  final LoanDraft draft;
}

class DispatchRepaymentDialog extends QuickDispatch {
  const DispatchRepaymentDialog({required this.loanId, this.draft});
  final String loanId;
  final RepaymentDraft? draft;
}

class DispatchAccountForm extends QuickDispatch {
  const DispatchAccountForm(this.draft);
  final AccountDraft draft;
}

class DispatchCategoryForm extends QuickDispatch {
  const DispatchCategoryForm(this.draft);
  final CategoryDraft draft;
}

class DispatchBudgetForm extends QuickDispatch {
  const DispatchBudgetForm(this.draft);
  final BudgetDraft draft;
}

class DispatchTemplateForm extends QuickDispatch {
  const DispatchTemplateForm(this.draft);
  final TemplateDraft draft;
}

class DispatchRecurringForm extends QuickDispatch {
  const DispatchRecurringForm(this.draft);
  final RecurringDraft draft;
}

/// The live app data [resolveQuickCommand] matches typed names against.
///
/// Passed in rather than read from providers directly, so the resolver stays
/// a pure function, testable with plain lists (AGENTS.md §22).
class QuickEntryLookups {
  const QuickEntryLookups({
    this.accounts = const [],
    this.incomeCategories = const [],
    this.expenseCategories = const [],
    this.anyCategories = const [],
    this.outstandingLoans = const [],
  });

  final List<FinancialAccountRow> accounts;
  final List<CategoryRow> incomeCategories;
  final List<CategoryRow> expenseCategories;
  final List<CategoryRow> anyCategories;
  final List<LoanProgress> outstandingLoans;
}

/// Converts a parsed command's raw string values into a [QuickDispatch].
///
/// Deliberately light validation: only what's needed to land on the right
/// screen with the right values (a name that must resolve to a real
/// account/category/loan, an amount that must parse). Anything the target
/// screen's own Save button already validates — a non-zero amount, for
/// instance — is left to it, since quick entry always opens that screen for
/// review before anything is saved.
///
/// Throws [FormatException] with a user-readable message on anything that
/// can't be resolved.
QuickDispatch resolveQuickCommand({
  required QuickCommandSpec command,
  required Map<String, String> values,
  required QuickEntryLookups lookups,
}) {
  switch (command.key) {
    case 'income':
      return DispatchTransactionForm(
        _moneyMovementDraft(
          TransactionType.income,
          values,
          lookups,
          lookups.incomeCategories,
        ),
      );
    case 'expense':
      return DispatchTransactionForm(
        _moneyMovementDraft(
          TransactionType.expense,
          values,
          lookups,
          lookups.expenseCategories,
        ),
      );
    case 'transfer':
      return DispatchTransactionForm(_transferDraft(values, lookups));
    case 'lent':
      return DispatchLoanForm(_loanDraft(LoanDirection.lent, values, lookups));
    case 'borrowed':
      return DispatchLoanForm(
        _loanDraft(LoanDirection.borrowed, values, lookups),
      );
    case 'repay':
      return _repayDispatch(values, lookups);
    case 'account':
      return DispatchAccountForm(_accountDraft(values));
    case 'category':
      return DispatchCategoryForm(_categoryDraft(values));
    case 'budget':
      return DispatchBudgetForm(_budgetDraft(values, lookups));
    case 'template':
      return DispatchTemplateForm(_templateDraft(values, lookups));
    case 'recurring':
      return DispatchRecurringForm(_recurringDraft(values, lookups));
  }
  throw StateError('Unhandled quick-entry command: ${command.key}');
}

// ---------------------------------------------------------------------------
// Per-command draft builders
// ---------------------------------------------------------------------------

TransactionDraft _moneyMovementDraft(
  TransactionType type,
  Map<String, String> values,
  QuickEntryLookups lookups,
  List<CategoryRow> categories,
) {
  return TransactionDraft(
    type: type,
    amountMinor: _requiredAmount(values['amount']),
    date: _optionalDate(values['date']),
    accountId: _accountId(values['account'], lookups.accounts, required: true),
    categoryId: _categoryId(values['category'], categories),
    description: values['description']?.trim() ?? '',
  );
}

TransactionDraft _transferDraft(
  Map<String, String> values,
  QuickEntryLookups lookups,
) {
  final fromId = _accountId(
    values['account'],
    lookups.accounts,
    required: true,
  );
  final toId = _accountId(
    values['destinationAccount'],
    lookups.accounts,
    required: true,
  );
  if (fromId == toId) {
    throw const FormatException('The destination must differ from the source');
  }
  return TransactionDraft(
    type: TransactionType.transfer,
    amountMinor: _requiredAmount(values['amount']),
    date: _optionalDate(values['date']),
    accountId: fromId,
    destinationAccountId: toId,
    description: values['description']?.trim() ?? '',
  );
}

LoanDraft _loanDraft(
  LoanDirection direction,
  Map<String, String> values,
  QuickEntryLookups lookups,
) {
  return LoanDraft(
    direction: direction,
    name: _requiredText(
      values['name'],
      direction == LoanDirection.lent ? 'who owes you' : 'who you owe',
    ),
    principalMinor: _requiredAmount(values['amount']),
    disbursementAccountId: _accountId(values['account'], lookups.accounts),
    startDate: _optionalDate(values['date']),
    description: values['description']?.trim() ?? '',
  );
}

QuickDispatch _repayDispatch(
  Map<String, String> values,
  QuickEntryLookups lookups,
) {
  final loan = _requiredLoan(values['loan'], lookups.outstandingLoans);
  return DispatchRepaymentDialog(
    loanId: loan.loan.id,
    draft: RepaymentDraft(
      amountMinor: _optionalAmount(values['amount']),
      accountId: _accountId(values['account'], lookups.accounts),
      date: _optionalDate(values['date']),
    ),
  );
}

AccountDraft _accountDraft(Map<String, String> values) {
  return AccountDraft(
    name: _requiredText(values['name'], 'name'),
    type: _matchStaticOrDefault(
      values['type'],
      quickAccountTypeLabels,
      AccountType.bank,
      'account type',
    ),
    openingBalanceMinor: _optionalAmount(values['amount']),
  );
}

CategoryDraft _categoryDraft(Map<String, String> values) {
  return CategoryDraft(
    name: _requiredText(values['name'], 'name'),
    type: _matchStaticOrDefault(
      values['type'],
      quickCategoryTypeLabels,
      CategoryType.expense,
      'category type',
    ),
  );
}

BudgetDraft _budgetDraft(
  Map<String, String> values,
  QuickEntryLookups lookups,
) {
  final categoryId = _categoryId(values['category'], lookups.expenseCategories);
  if (categoryId == null) throw const FormatException('Choose a category');
  return BudgetDraft(
    categoryId: categoryId,
    amountMinor: _requiredAmount(values['amount']),
    period: _matchStaticOrDefault(
      values['period'],
      quickBudgetPeriodLabels,
      BudgetPeriod.monthly,
      'period',
    ),
  );
}

TemplateDraft _templateDraft(
  Map<String, String> values,
  QuickEntryLookups lookups,
) {
  return TemplateDraft(
    name: _requiredText(values['name'], 'name'),
    type: _matchStaticOrDefault(
      values['type'],
      quickPresetTransactionTypeLabels,
      TransactionType.expense,
      'type',
    ),
    amountMinor: _optionalAmount(values['amount']),
    accountId: _accountId(values['account'], lookups.accounts),
    categoryId: _categoryId(values['category'], lookups.anyCategories),
    description: values['description']?.trim() ?? '',
  );
}

RecurringDraft _recurringDraft(
  Map<String, String> values,
  QuickEntryLookups lookups,
) {
  return RecurringDraft(
    name: _requiredText(values['name'], 'name'),
    amountMinor: _requiredAmount(values['amount']),
    accountId: _accountId(values['account'], lookups.accounts, required: true),
    frequency: _matchStaticOrDefault(
      values['frequency'],
      quickRecurrenceFrequencyLabels,
      RecurrenceFrequency.monthly,
      'frequency',
    ),
    description: values['description']?.trim() ?? '',
  );
}

// ---------------------------------------------------------------------------
// Field-level parsing/matching helpers
// ---------------------------------------------------------------------------

int _requiredAmount(String? raw) {
  final input = raw?.trim() ?? '';
  if (input.isEmpty) throw const FormatException('Enter an amount');
  return parseMinorUnits(input);
}

int? _optionalAmount(String? raw) {
  final input = raw?.trim() ?? '';
  if (input.isEmpty) return null;
  return parseMinorUnits(input);
}

/// Accepts an ISO calendar date (as the `@` date picker inserts) or the word
/// `today`; anything else is rejected with a message pointing at `@`.
DateTime? _optionalDate(String? raw) {
  final input = raw?.trim() ?? '';
  if (input.isEmpty) return null;
  if (input.toLowerCase() == 'today') return DateTime.now();
  final parsed = DateTime.tryParse(input);
  if (parsed == null) {
    throw FormatException('Enter a date like 2026-08-12, or use @ to pick one');
  }
  return parsed;
}

String _requiredText(String? raw, String label) {
  final input = raw?.trim() ?? '';
  if (input.isEmpty) throw FormatException('Enter a $label');
  return input;
}

T? _matchByName<T>(
  String? raw,
  List<T> items,
  String Function(T) nameOf,
  String kind,
) {
  final input = raw?.trim() ?? '';
  if (input.isEmpty) return null;
  final needle = input.toLowerCase();
  for (final item in items) {
    if (nameOf(item).toLowerCase() == needle) return item;
  }
  throw FormatException('No $kind named "$input"');
}

String? _accountId(
  String? raw,
  List<FinancialAccountRow> accounts, {
  bool required = false,
}) {
  final match = _matchByName(raw, accounts, (a) => a.name, 'account');
  if (match == null && required) {
    throw const FormatException('Choose an account');
  }
  return match?.id;
}

String? _categoryId(String? raw, List<CategoryRow> categories) =>
    _matchByName(raw, categories, (c) => c.name, 'category')?.id;

LoanProgress _requiredLoan(String? raw, List<LoanProgress> loans) {
  final input = raw?.trim() ?? '';
  if (input.isEmpty) throw const FormatException('Choose a loan');
  final needle = input.toLowerCase();
  for (final loan in loans) {
    if (loan.loan.name.toLowerCase() == needle) return loan;
  }
  throw FormatException('No outstanding loan named "$input"');
}

T _matchStaticOrDefault<T>(
  String? raw,
  Map<T, String> labels,
  T fallback,
  String kind,
) {
  final input = raw?.trim() ?? '';
  if (input.isEmpty) return fallback;
  final match = matchQuickStaticOption(raw, labels);
  if (match == null) throw FormatException('Unknown $kind "$input"');
  return match;
}
