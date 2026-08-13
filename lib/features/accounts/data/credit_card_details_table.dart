import 'package:drift/drift.dart';

import 'account_table.dart';

/// Drift table for a credit card's billing details (docs/DATA_MODEL.md §60,
/// ADR-005).
///
/// One-to-one with [FinancialAccounts] via [accountId] — mirrors how `loans`
/// relates to an account (ADR-004): a separate table rather than nullable
/// columns on `financial_accounts` itself, so every non-credit-card account
/// has no meaningless null fields.
///
/// Everything about the current cycle — outstanding balance, available
/// credit, the previous statement's balance, the next statement date, the
/// payment due date — is deliberately absent here. All of it is derived at
/// read time from these three fields plus the transactions table
/// (`CreditCardCycle`), never stored, so it can never disagree with the
/// transactions behind it (mirrors ADR-004 §3 for loans).
@DataClassName('CreditCardDetailsRow')
class CreditCardDetails extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  TextColumn get id => text()();

  /// The account this billing detail belongs to. Unique: a credit-card
  /// account has exactly one details row.
  TextColumn get accountId =>
      text().references(FinancialAccounts, #id).unique()();

  /// The card's credit limit, in integer minor units; always > 0.
  IntColumn get creditLimitMinor => integer()();

  /// Day of the month (1–31) the statement closes. Clamped to the last valid
  /// day of shorter months when deriving an actual date
  /// (`statementDateOnOrBefore`).
  IntColumn get statementDay => integer()();

  /// How many days after the statement closes payment is due. An offset
  /// rather than a second day-of-month, so the due date is unambiguous
  /// regardless of how it compares to [statementDay] (ADR-005).
  IntColumn get paymentDueOffsetDays => integer()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
