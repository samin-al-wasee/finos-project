import 'package:drift/drift.dart';

import '../../accounts/data/account_table.dart';
import '../domain/loan_direction.dart';
import '../domain/loan_status.dart';

/// Drift table for loans (docs/DATA_MODEL.md §29–§33, ADR-004).
///
/// A loan records the agreement; the money moving is recorded as transactions
/// carrying this loan's id. Two fields from the conceptual model are deliberately
/// absent:
///
/// * `outstanding_amount` — derived as `principal − Σ(repayments)` so it can never
///   disagree with the repayments behind it (docs/DATA_MODEL.md §45).
/// * `PAID` / `OVERDUE` status — derived from repayments and [dueDate]; only the
///   `ACTIVE`/`ARCHIVED` lifecycle is stored.
@DataClassName('LoanRow')
class Loans extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  TextColumn get id => text()();

  /// Lent (a receivable) or borrowed (a liability) — docs/DATA_MODEL.md §29.
  TextColumn get type => text().map(const LoanDirectionConverter())();

  /// Who the loan is with, e.g. `John` or `Bank Loan`.
  TextColumn get name => text()();

  /// The original amount in integer minor units; always > 0
  /// (docs/DATA_MODEL.md §46).
  IntColumn get principalMinor => integer()();

  /// ISO 4217 currency code — docs/DATA_MODEL.md §5.
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('BDT'))();

  /// The calendar date the loan was made.
  DateTimeColumn get startDate => dateTime()();

  /// Optional date the loan is due to be settled. A past date with an
  /// outstanding balance makes the loan overdue.
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Optional user note.
  TextColumn get description => text().withDefault(const Constant(''))();

  /// The account the principal moved through when the loan was made.
  ///
  /// Null for a loan that pre-dates FinOS: it is opening state, exactly as an
  /// account's opening balance is (docs/DATA_MODEL.md §9), and no origination
  /// transaction exists for it. When set, creating the loan also records the cash
  /// movement (ADR-004).
  TextColumn get disbursementAccountId =>
      text().nullable().references(FinancialAccounts, #id)();

  /// Stored lifecycle state — docs/DATA_MODEL.md §33, §39.
  TextColumn get status => text()
      .map(const LoanStatusConverter())
      .withDefault(const Constant('ACTIVE'))();

  /// The relationship this loan belongs to, when it is an extension of (or has
  /// been extended by) another loan. Points at the *root* loan of the
  /// relationship — the first one created — so every member of a relationship
  /// shares one value and grouping needs no recursive traversal
  /// (docs/adr/006-loan-relationships.md).
  TextColumn get groupId => text().nullable().references(Loans, #id)();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
