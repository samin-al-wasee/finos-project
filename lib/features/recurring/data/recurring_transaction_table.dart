import 'package:drift/drift.dart';

import '../../accounts/data/account_table.dart';
import '../../categories/data/category_table.dart';
import '../../transactions/domain/transaction_type.dart';
import '../domain/recurrence_frequency.dart';
import '../domain/recurring_status.dart';

/// Drift table for recurring transaction rules (docs/DATA_MODEL.md §26,
/// docs/ROADMAP.md §8.1).
///
/// A rule is not itself a transaction (docs/DATA_MODEL.md §28) — it generates
/// one only when a due occurrence is confirmed. Unlike a template (whose
/// fields are mostly optional presets), every field needed to actually create
/// a transaction is required here, because generation runs unattended.
@DataClassName('RecurringTransactionRow')
class RecurringTransactions extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  TextColumn get id => text()();

  /// Short label, e.g. "Netflix".
  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// Income, expense, or transfer. Loan movements are never recurring rules —
  /// they are created only through the loan feature (ADR-004).
  TextColumn get type => text().map(const TransactionTypeConverter())();

  /// Amount in integer minor units; always > 0 — docs/DATA_MODEL.md §46.
  IntColumn get amountMinor => integer()();

  /// The account each generated transaction is paid into/out of, or the
  /// source of a transfer.
  TextColumn get accountId => text().references(FinancialAccounts, #id)();

  /// The receiving account — transfer rules only.
  TextColumn get destinationAccountId =>
      text().nullable().references(FinancialAccounts, #id)();

  /// Category — income/expense rules only.
  TextColumn get categoryId => text().nullable().references(Categories, #id)();

  TextColumn get description => text().withDefault(const Constant(''))();

  TextColumn get frequency =>
      text().map(const RecurrenceFrequencyConverter())();

  /// The calendar date the rule takes effect.
  DateTimeColumn get startDate => dateTime()();

  /// The next date this rule is due. Advances every time an occurrence is
  /// confirmed or skipped — this is the only mutable scheduling state
  /// (docs/DATA_MODEL.md §26).
  DateTimeColumn get nextOccurrence => dateTime()();

  /// Inclusive last date this rule is due, or null to repeat indefinitely.
  DateTimeColumn get endDate => dateTime().nullable()();

  TextColumn get status => text()
      .map(const RecurringStatusConverter())
      .withDefault(const Constant('ACTIVE'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
