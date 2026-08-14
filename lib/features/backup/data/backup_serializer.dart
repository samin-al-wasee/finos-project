import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../accounts/domain/account_status.dart';
import '../../accounts/domain/account_type.dart';
import '../../budgets/domain/budget_period.dart';
import '../../budgets/domain/budget_scope.dart';
import '../../budgets/domain/budget_status.dart';
import '../../categories/domain/category_origin.dart';
import '../../categories/domain/category_status.dart';
import '../../categories/domain/category_type.dart';
import '../../investments/domain/investment_contribution_mode.dart';
import '../../investments/domain/investment_instrument_type.dart';
import '../../investments/domain/investment_payout_frequency.dart';
import '../../investments/domain/investment_status.dart';
import '../../loans/domain/loan_direction.dart';
import '../../loans/domain/loan_status.dart';
import '../../transactions/domain/transaction_type.dart';

/// Converts database rows to and from the JSON maps in a backup file.
///
/// Reading is deliberately strict: every field is checked for presence and type,
/// and anything unrecognised raises a [ValidationException] carrying a message
/// naming the record and field. Malformed data must be rejected before any
/// database work begins (AGENTS.md §14), and the user needs to know *which*
/// record is wrong.
///
/// Dates are written as ISO-8601 local wall-clock strings with no timezone
/// designator, and parsed back as local. A calendar date therefore survives a
/// round trip unchanged instead of shifting a day across timezones
/// (docs/DATA_MODEL.md §42).
abstract final class BackupSerializer {
  // ------------------------------------------------------------------
  // Write
  // ------------------------------------------------------------------

  static Map<String, Object?> accountToJson(FinancialAccountRow row) => {
    'id': row.id,
    'name': row.name,
    'type': const AccountTypeConverter().toSql(row.type),
    'currency': row.currency,
    'opening_balance_minor': row.openingBalanceMinor,
    'status': const AccountStatusConverter().toSql(row.status),
    'created_at': _dateToJson(row.createdAt),
    'updated_at': _dateToJson(row.updatedAt),
  };

  static Map<String, Object?> categoryToJson(CategoryRow row) => {
    'id': row.id,
    'name': row.name,
    'type': const CategoryTypeConverter().toSql(row.type),
    'origin': const CategoryOriginConverter().toSql(row.origin),
    'icon': row.icon,
    'status': const CategoryStatusConverter().toSql(row.status),
    'created_at': _dateToJson(row.createdAt),
    'updated_at': _dateToJson(row.updatedAt),
  };

  static Map<String, Object?> transactionToJson(TransactionRow row) => {
    'id': row.id,
    'type': const TransactionTypeConverter().toSql(row.type),
    'amount_minor': row.amountMinor,
    'currency': row.currency,
    'account_id': row.accountId,
    'destination_account_id': row.destinationAccountId,
    'category_id': row.categoryId,
    'loan_id': row.loanId,
    'investment_id': row.investmentId,
    'date': _dateToJson(row.date),
    'description': row.description,
    'created_at': _dateToJson(row.createdAt),
    'updated_at': _dateToJson(row.updatedAt),
  };

  static Map<String, Object?> loanToJson(LoanRow row) => {
    'id': row.id,
    'type': const LoanDirectionConverter().toSql(row.type),
    'name': row.name,
    'principal_minor': row.principalMinor,
    'currency': row.currency,
    'start_date': _dateToJson(row.startDate),
    'due_date': row.dueDate == null ? null : _dateToJson(row.dueDate!),
    'description': row.description,
    'disbursement_account_id': row.disbursementAccountId,
    'status': const LoanStatusConverter().toSql(row.status),
    'group_id': row.groupId,
    'created_at': _dateToJson(row.createdAt),
    'updated_at': _dateToJson(row.updatedAt),
  };

  static Map<String, Object?> investmentToJson(InvestmentRow row) => {
    'id': row.id,
    'name': row.name,
    'instrument_type': const InvestmentInstrumentTypeConverter().toSql(
      row.instrumentType,
    ),
    'contribution_mode': const InvestmentContributionModeConverter().toSql(
      row.contributionMode,
    ),
    'amount_minor': row.amountMinor,
    'currency': row.currency,
    'source_account_id': row.sourceAccountId,
    'payout_account_id': row.payoutAccountId,
    'start_date': _dateToJson(row.startDate),
    'maturity_date': _dateToJson(row.maturityDate),
    'payout_frequency': const InvestmentPayoutFrequencyConverter().toSql(
      row.payoutFrequency,
    ),
    'next_contribution_due': row.nextContributionDue == null
        ? null
        : _dateToJson(row.nextContributionDue!),
    'next_payout_due': row.nextPayoutDue == null
        ? null
        : _dateToJson(row.nextPayoutDue!),
    'status': const InvestmentStatusConverter().toSql(row.status),
    'created_at': _dateToJson(row.createdAt),
    'updated_at': _dateToJson(row.updatedAt),
  };

  /// [categoryIds] is the budget's `budget_categories` join rows — only ever
  /// non-empty for a `MULTI_CATEGORY` budget
  /// (docs/adr/007-flexible-budget-scope.md) — and is written as a
  /// `category_ids` array only when non-empty, so a `SINGLE_CATEGORY`-only
  /// backup is byte-for-byte what it always was.
  static Map<String, Object?> budgetToJson(
    BudgetRow row, {
    Set<String> categoryIds = const {},
  }) => {
    'id': row.id,
    'category_id': row.categoryId,
    'scope_type': const BudgetScopeTypeConverter().toSql(row.scopeType),
    if (categoryIds.isNotEmpty) 'category_ids': categoryIds.toList()..sort(),
    'amount_minor': row.amountMinor,
    'currency': row.currency,
    'period': const BudgetPeriodConverter().toSql(row.period),
    'start_date': _dateToJson(row.startDate),
    'end_date': row.endDate == null ? null : _dateToJson(row.endDate!),
    'status': const BudgetStatusConverter().toSql(row.status),
    'created_at': _dateToJson(row.createdAt),
    'updated_at': _dateToJson(row.updatedAt),
    'rollover_enabled': row.rolloverEnabled,
  };

  // ------------------------------------------------------------------
  // Read
  // ------------------------------------------------------------------

  static FinancialAccountRow accountFromJson(Map<String, Object?> json) {
    const where = 'account';
    return FinancialAccountRow(
      id: _id(json, where),
      name: _string(json, 'name', where),
      type: _enumValue(
        json,
        'type',
        where,
        const AccountTypeConverter().fromSql,
      ),
      currency: _currency(json, where),
      openingBalanceMinor: _int(json, 'opening_balance_minor', where),
      status: _enumValue(
        json,
        'status',
        where,
        const AccountStatusConverter().fromSql,
      ),
      createdAt: _date(json, 'created_at', where),
      updatedAt: _date(json, 'updated_at', where),
    );
  }

  static CategoryRow categoryFromJson(Map<String, Object?> json) {
    const where = 'category';
    return CategoryRow(
      id: _id(json, where),
      name: _string(json, 'name', where),
      type: _enumValue(
        json,
        'type',
        where,
        const CategoryTypeConverter().fromSql,
      ),
      origin: _enumValue(
        json,
        'origin',
        where,
        const CategoryOriginConverter().fromSql,
      ),
      icon: _string(json, 'icon', where),
      status: _enumValue(
        json,
        'status',
        where,
        const CategoryStatusConverter().fromSql,
      ),
      createdAt: _date(json, 'created_at', where),
      updatedAt: _date(json, 'updated_at', where),
    );
  }

  static TransactionRow transactionFromJson(Map<String, Object?> json) {
    const where = 'transaction';
    final amountMinor = _int(json, 'amount_minor', where);
    // The invariant from docs/DATA_MODEL.md §46. A non-positive amount would
    // silently corrupt every balance derived from it.
    if (amountMinor <= 0) {
      throw ValidationException(
        'A transaction in the backup has an amount of $amountMinor; '
        'amounts must be greater than zero.',
      );
    }
    return TransactionRow(
      id: _id(json, where),
      type: _enumValue(
        json,
        'type',
        where,
        const TransactionTypeConverter().fromSql,
      ),
      amountMinor: amountMinor,
      currency: _currency(json, where),
      accountId: _string(json, 'account_id', where),
      destinationAccountId: _optionalString(
        json,
        'destination_account_id',
        where,
      ),
      categoryId: _optionalString(json, 'category_id', where),
      loanId: _optionalString(json, 'loan_id', where),
      investmentId: _optionalString(json, 'investment_id', where),
      date: _date(json, 'date', where),
      description: _string(json, 'description', where, allowEmpty: true),
      createdAt: _date(json, 'created_at', where),
      updatedAt: _date(json, 'updated_at', where),
    );
  }

  static LoanRow loanFromJson(Map<String, Object?> json) {
    const where = 'loan';
    final principalMinor = _int(json, 'principal_minor', where);
    // The invariant from docs/DATA_MODEL.md §46.
    if (principalMinor <= 0) {
      throw ValidationException(
        'A loan in the backup has a principal of $principalMinor; '
        'it must be greater than zero.',
      );
    }
    final dueDateValue = json['due_date'];
    return LoanRow(
      id: _id(json, where),
      type: _enumValue(
        json,
        'type',
        where,
        const LoanDirectionConverter().fromSql,
      ),
      name: _string(json, 'name', where),
      principalMinor: principalMinor,
      currency: _currency(json, where),
      startDate: _date(json, 'start_date', where),
      dueDate: dueDateValue == null ? null : _date(json, 'due_date', where),
      description: _string(json, 'description', where, allowEmpty: true),
      disbursementAccountId: _optionalString(
        json,
        'disbursement_account_id',
        where,
      ),
      status: _enumValue(
        json,
        'status',
        where,
        const LoanStatusConverter().fromSql,
      ),
      groupId: _optionalString(json, 'group_id', where),
      createdAt: _date(json, 'created_at', where),
      updatedAt: _date(json, 'updated_at', where),
    );
  }

  static InvestmentRow investmentFromJson(Map<String, Object?> json) {
    const where = 'investment';
    final amountMinor = _int(json, 'amount_minor', where);
    // The invariant from docs/DATA_MODEL.md §46.
    if (amountMinor <= 0) {
      throw ValidationException(
        'An investment in the backup has an amount of $amountMinor; '
        'it must be greater than zero.',
      );
    }
    final nextContributionDueValue = json['next_contribution_due'];
    final nextPayoutDueValue = json['next_payout_due'];
    return InvestmentRow(
      id: _id(json, where),
      name: _string(json, 'name', where),
      instrumentType: _enumValue(
        json,
        'instrument_type',
        where,
        const InvestmentInstrumentTypeConverter().fromSql,
      ),
      contributionMode: _enumValue(
        json,
        'contribution_mode',
        where,
        const InvestmentContributionModeConverter().fromSql,
      ),
      amountMinor: amountMinor,
      currency: _currency(json, where),
      sourceAccountId: _string(json, 'source_account_id', where),
      payoutAccountId: _string(json, 'payout_account_id', where),
      startDate: _date(json, 'start_date', where),
      maturityDate: _date(json, 'maturity_date', where),
      payoutFrequency: _enumValue(
        json,
        'payout_frequency',
        where,
        const InvestmentPayoutFrequencyConverter().fromSql,
      ),
      nextContributionDue: nextContributionDueValue == null
          ? null
          : _date(json, 'next_contribution_due', where),
      nextPayoutDue: nextPayoutDueValue == null
          ? null
          : _date(json, 'next_payout_due', where),
      status: _enumValue(
        json,
        'status',
        where,
        const InvestmentStatusConverter().fromSql,
      ),
      createdAt: _date(json, 'created_at', where),
      updatedAt: _date(json, 'updated_at', where),
    );
  }

  /// Reads a budget row. `scope_type` defaults to `SINGLE_CATEGORY` when
  /// absent, mirroring the column's own default, so a backup written before
  /// this feature existed — which has no `scope_type` field at all — still
  /// restores unchanged (docs/adr/007-flexible-budget-scope.md).
  /// `category_id` is optional for the same reason `budgetToJson` only
  /// writes it as before: it is `NULL` for every scope type except
  /// `SINGLE_CATEGORY`. `rollover_enabled` defaults to `false` when absent,
  /// mirroring the column's own default, so a backup written before this
  /// feature existed restores unchanged (docs/adr/008-budget-rollover.md).
  static BudgetRow budgetFromJson(Map<String, Object?> json) {
    const where = 'budget';
    final amountMinor = _int(json, 'amount_minor', where);
    // The invariant from docs/DATA_MODEL.md §46.
    if (amountMinor <= 0) {
      throw ValidationException(
        'A budget in the backup has a limit of $amountMinor; '
        'limits must be greater than zero.',
      );
    }
    final scopeType = json['scope_type'] == null
        ? BudgetScopeType.singleCategory
        : _enumValue(
            json,
            'scope_type',
            where,
            const BudgetScopeTypeConverter().fromSql,
          );
    if (scopeType == BudgetScopeType.singleCategory &&
        json['category_id'] == null) {
      throw ValidationException(
        'A single-category budget in the backup has no category_id.',
      );
    }
    final endDateValue = json['end_date'];
    return BudgetRow(
      id: _id(json, where),
      categoryId: _optionalString(json, 'category_id', where),
      scopeType: scopeType,
      amountMinor: amountMinor,
      currency: _currency(json, where),
      period: _enumValue(
        json,
        'period',
        where,
        const BudgetPeriodConverter().fromSql,
      ),
      startDate: _date(json, 'start_date', where),
      endDate: endDateValue == null ? null : _date(json, 'end_date', where),
      status: _enumValue(
        json,
        'status',
        where,
        const BudgetStatusConverter().fromSql,
      ),
      createdAt: _date(json, 'created_at', where),
      updatedAt: _date(json, 'updated_at', where),
      rolloverEnabled: _boolWithDefault(
        json,
        'rollover_enabled',
        where,
        fallback: false,
      ),
    );
  }

  /// Reads a budget's `category_ids` array — only ever present for a
  /// `MULTI_CATEGORY` budget. Returns an empty set when absent, since every
  /// other scope type never has one.
  static Set<String> budgetCategoryIdsFromJson(Map<String, Object?> json) {
    const where = 'budget';
    final value = json['category_ids'];
    if (value == null) return const {};
    if (value is! List) {
      throw ValidationException(
        _typeMessage(where, 'category_ids', 'a list', value),
      );
    }
    final ids = <String>{};
    for (final entry in value) {
      if (entry is! String || entry.isEmpty) {
        throw ValidationException(
          'A $where in the backup has an invalid entry in category_ids.',
        );
      }
      ids.add(entry);
    }
    return ids;
  }

  // ------------------------------------------------------------------
  // Field readers
  // ------------------------------------------------------------------

  /// Writes a [DateTime] as a local wall-clock ISO-8601 string.
  ///
  /// No `Z` suffix and no offset: [DateTime.parse] reads it back as local time
  /// with the same wall clock, so the calendar date is preserved.
  static String _dateToJson(DateTime value) =>
      value.toLocal().toIso8601String();

  static String _id(Map<String, Object?> json, String where) =>
      _string(json, 'id', where);

  static String _string(
    Map<String, Object?> json,
    String field,
    String where, {
    bool allowEmpty = false,
  }) {
    final value = json[field];
    if (value is! String) {
      throw ValidationException(_typeMessage(where, field, 'text', value));
    }
    if (!allowEmpty && value.isEmpty) {
      throw ValidationException('A $where in the backup has an empty $field.');
    }
    return value;
  }

  static String? _optionalString(
    Map<String, Object?> json,
    String field,
    String where,
  ) {
    final value = json[field];
    if (value == null) return null;
    if (value is! String) {
      throw ValidationException(_typeMessage(where, field, 'text', value));
    }
    return value;
  }

  static int _int(Map<String, Object?> json, String field, String where) {
    final value = json[field];
    // Explicitly reject doubles: money is integer minor units, never floating
    // point (docs/DATA_MODEL.md §4). A JSON `1500.0` must not become 1500 here,
    // because it signals a producer that lost precision somewhere upstream.
    if (value is! int) {
      throw ValidationException(
        _typeMessage(where, field, 'a whole number', value),
      );
    }
    return value;
  }

  /// Reads a boolean field, defaulting to [fallback] when [field] is absent —
  /// used for a column added after backups already existed, mirroring the
  /// column's own schema default (docs/adr/008-budget-rollover.md).
  static bool _boolWithDefault(
    Map<String, Object?> json,
    String field,
    String where, {
    required bool fallback,
  }) {
    final value = json[field];
    if (value == null) return fallback;
    if (value is! bool) {
      throw ValidationException(
        _typeMessage(where, field, 'true/false', value),
      );
    }
    return value;
  }

  static String _currency(Map<String, Object?> json, String where) {
    final value = _string(json, 'currency', where);
    if (value.length != 3) {
      throw ValidationException(
        'A $where in the backup has currency "$value"; expected a '
        'three-letter code.',
      );
    }
    return value;
  }

  static DateTime _date(Map<String, Object?> json, String field, String where) {
    final value = _string(json, field, where);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw ValidationException(
        'A $where in the backup has an unreadable $field: "$value".',
      );
    }
    return parsed;
  }

  /// Reads an enum via its storage converter, turning the converter's
  /// [ArgumentError] into a user-facing message.
  static T _enumValue<T>(
    Map<String, Object?> json,
    String field,
    String where,
    T Function(String) fromSql,
  ) {
    final value = _string(json, field, where);
    try {
      return fromSql(value);
    } on ArgumentError {
      throw ValidationException(
        'A $where in the backup has an unrecognised $field: "$value".',
      );
    }
  }

  static String _typeMessage(
    String where,
    String field,
    String expected,
    Object? actual,
  ) {
    final describedValue = actual == null ? 'nothing' : '"$actual"';
    return 'A $where in the backup has an invalid $field: expected '
        '$expected but found $describedValue.';
  }
}
