import 'package:drift/drift.dart';

import '../../accounts/data/account_table.dart';
import '../../categories/data/category_table.dart';
import '../../investments/data/investment_table.dart';
import '../../loans/data/loan_table.dart';
import '../../savings_goals/data/savings_goal_table.dart';
import '../domain/transaction_type.dart';

/// Drift table for financial transactions (docs/DATA_MODEL.md §11).
///
/// Amounts are stored as integer minor units (never binary floating point) per
/// docs/DATA_MODEL.md §4. The amount is always positive; the direction money
/// moves is implied by [type]. Transfers set [accountId] (source) and
/// [destinationAccountId] together and leave [categoryId] null.
@DataClassName('TransactionRow')
class Transactions extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  TextColumn get id => text()();

  /// Income, expense, or transfer — docs/DATA_MODEL.md §12.
  TextColumn get type => text().map(const TransactionTypeConverter())();

  /// Amount in integer minor units; always > 0 — docs/DATA_MODEL.md §46.
  IntColumn get amountMinor => integer()();

  /// ISO 4217 currency code — docs/DATA_MODEL.md §5.
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('BDT'))();

  /// The account money is paid into (income), paid out of (expense), or the
  /// source of a transfer — docs/DATA_MODEL.md §44.
  TextColumn get accountId => text().references(FinancialAccounts, #id)();

  /// For transfers only: the receiving account. Null otherwise.
  TextColumn get destinationAccountId =>
      text().nullable().references(FinancialAccounts, #id)();

  /// Optional category classifying income/expense. Always null for transfers and
  /// loan movements, because neither may affect spending or income totals
  /// (docs/DATA_MODEL.md §17, ADR-004).
  TextColumn get categoryId => text().nullable().references(Categories, #id)();

  /// The loan this movement belongs to. Set only for `LOAN_RECEIPT` and
  /// `LOAN_PAYMENT` rows, and null for all ordinary activity (ADR-004).
  TextColumn get loanId => text().nullable().references(Loans, #id)();

  /// The investment this movement belongs to. Set only for
  /// `INVESTMENT_CONTRIBUTION` and `INVESTMENT_PAYOUT` rows, and null for all
  /// ordinary activity (docs/adr/009-investment-accounting.md). [accountId]
  /// carries the actual account affected — the investment's source account for
  /// a contribution, its payout account for a payout — the same way a loan
  /// movement's [accountId] is whichever account the loan's cash moved
  /// through.
  TextColumn get investmentId =>
      text().nullable().references(Investments, #id)();

  /// The savings goal this movement belongs to. Set only for
  /// `SAVINGS_CONTRIBUTION` and `SAVINGS_WITHDRAWAL` rows, and null for all
  /// ordinary activity (docs/adr/011-savings-goals.md). [accountId] carries
  /// the goal's single linked account for both directions, unlike a loan or
  /// investment movement, which can differ per type.
  TextColumn get savingsGoalId =>
      text().nullable().references(SavingsGoals, #id)();

  /// The calendar date the financial event happened (docs/DATA_MODEL.md §41).
  /// This is the financial event date, not the record-creation timestamp.
  DateTimeColumn get date => dateTime()();

  /// Optional user note — docs/DATA_MODEL.md §11.
  TextColumn get description => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
