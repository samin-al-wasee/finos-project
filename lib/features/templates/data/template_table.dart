import 'package:drift/drift.dart';

import '../../accounts/data/account_table.dart';
import '../../categories/data/category_table.dart';
import '../../transactions/domain/transaction_type.dart';

/// Drift table for saved transaction templates (docs/ROADMAP.md §8.2).
///
/// A template is a preset for *manual* entry: using one pre-fills the
/// transaction form for the user to review and save. It never creates a
/// transaction by itself — that would be recurring transactions
/// (docs/ROADMAP.md §8.1), a distinct, explicitly out-of-scope feature.
@DataClassName('TransactionTemplateRow')
class TransactionTemplates extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  TextColumn get id => text()();

  /// Short label shown in the template list, e.g. "Netflix".
  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// Income, expense, or transfer. Loan movements are never templated — they
  /// are created only through the loan feature (ADR-004).
  TextColumn get type => text().map(const TransactionTypeConverter())();

  /// Preset amount in integer minor units, or null to leave it blank for the
  /// user to fill in each time — e.g. a subscription whose price varies.
  IntColumn get amountMinor => integer().nullable()();

  /// Preset source account, or null to leave unset.
  TextColumn get accountId =>
      text().nullable().references(FinancialAccounts, #id)();

  /// Preset destination account — transfer templates only.
  TextColumn get destinationAccountId =>
      text().nullable().references(FinancialAccounts, #id)();

  /// Preset category — income/expense templates only.
  TextColumn get categoryId => text().nullable().references(Categories, #id)();

  /// Preset note, prefilled into the transaction's description.
  TextColumn get description => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
