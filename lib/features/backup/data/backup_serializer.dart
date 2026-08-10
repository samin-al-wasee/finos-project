import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../accounts/domain/account_status.dart';
import '../../accounts/domain/account_type.dart';
import '../../budgets/domain/budget_period.dart';
import '../../budgets/domain/budget_status.dart';
import '../../categories/domain/category_origin.dart';
import '../../categories/domain/category_status.dart';
import '../../categories/domain/category_type.dart';
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
    'date': _dateToJson(row.date),
    'description': row.description,
    'created_at': _dateToJson(row.createdAt),
    'updated_at': _dateToJson(row.updatedAt),
  };

  static Map<String, Object?> budgetToJson(BudgetRow row) => {
    'id': row.id,
    'category_id': row.categoryId,
    'amount_minor': row.amountMinor,
    'currency': row.currency,
    'period': const BudgetPeriodConverter().toSql(row.period),
    'start_date': _dateToJson(row.startDate),
    'end_date': row.endDate == null ? null : _dateToJson(row.endDate!),
    'status': const BudgetStatusConverter().toSql(row.status),
    'created_at': _dateToJson(row.createdAt),
    'updated_at': _dateToJson(row.updatedAt),
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
      date: _date(json, 'date', where),
      description: _string(json, 'description', where, allowEmpty: true),
      createdAt: _date(json, 'created_at', where),
      updatedAt: _date(json, 'updated_at', where),
    );
  }

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
    final endDateValue = json['end_date'];
    return BudgetRow(
      id: _id(json, where),
      categoryId: _string(json, 'category_id', where),
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
    );
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
