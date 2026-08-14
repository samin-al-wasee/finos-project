import 'package:drift/drift.dart';

import '../../accounts/data/account_table.dart';
import '../domain/savings_goal_status.dart';

/// Drift table for savings goals (docs/adr/011-savings-goals.md).
///
/// A goal records the target; the money moving is recorded as transactions
/// carrying this goal's id, the same pattern
/// `lib/features/loans/data/loan_table.dart` uses for loans. Two fields from
/// the conceptual model are deliberately absent:
///
/// * `current_amount` — derived as `Σ(contributions) − Σ(withdrawals)` over
///   the goal's own transactions, so it can never disagree with the records
///   behind it.
/// * `ACHIEVED` status — derived by comparing that current amount against
///   [targetAmountMinor] at read time; only the `ACTIVE`/`ARCHIVED`
///   lifecycle is stored (see `SavingsGoalStatus`).
@DataClassName('SavingsGoalRow')
class SavingsGoals extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  TextColumn get id => text()();

  /// User-chosen name, e.g. "Emergency Fund" or "New Laptop".
  TextColumn get name => text()();

  /// What the goal is saving toward. Always > 0 (docs/DATA_MODEL.md §46).
  IntColumn get targetAmountMinor => integer()();

  /// ISO 4217 currency code — docs/DATA_MODEL.md §5.
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('BDT'))();

  /// The account contributions are debited from and withdrawals are
  /// credited to. A single field, unlike Investments' separate source/payout
  /// accounts — a goal is money set aside from the user's own accounts, not
  /// a separate financial product (docs/adr/011-savings-goals.md §1).
  TextColumn get accountId => text().references(FinancialAccounts, #id)();

  /// The calendar date the goal was created.
  DateTimeColumn get startDate => dateTime()();

  /// Optional target date. Not every goal has one.
  DateTimeColumn get deadlineDate => dateTime().nullable()();

  /// Optional user note.
  TextColumn get description => text().withDefault(const Constant(''))();

  /// Stored lifecycle state — see `SavingsGoalStatus`.
  TextColumn get status => text()
      .map(const SavingsGoalStatusConverter())
      .withDefault(const Constant('ACTIVE'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
