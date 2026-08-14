import 'package:drift/drift.dart';

import '../../accounts/data/account_table.dart';
import '../domain/investment_contribution_mode.dart';
import '../domain/investment_instrument_type.dart';
import '../domain/investment_payout_frequency.dart';
import '../domain/investment_status.dart';

/// Drift table for fixed-term investments — FDR, DPS, Sanchayapatra
/// (docs/adr/009-investment-accounting.md).
///
/// An investment records the agreement; the money moving is recorded as
/// transactions carrying this investment's id, the same pattern
/// `lib/features/loans/data/loan_table.dart` uses for loans. Two fields from
/// the conceptual model are deliberately absent:
///
/// * `contributed_amount` / `payout_received_amount` — derived as sums over
///   the investment's own transactions, so they can never disagree with the
///   records behind them.
/// * `MATURED` status — derived from [maturityDate] at read time; only the
///   `ACTIVE`/`ARCHIVED` lifecycle is stored (see `InvestmentStatus`).
@DataClassName('InvestmentRow')
class Investments extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  TextColumn get id => text()();

  /// User-chosen name, e.g. "5-year Sanchayapatra".
  TextColumn get name => text()();

  /// Which kind of instrument this is — purely descriptive, does not affect
  /// any calculation.
  TextColumn get instrumentType =>
      text().map(const InvestmentInstrumentTypeConverter())();

  /// Lump sum (FDR, Sanchayapatra) or recurring monthly deposits (DPS).
  TextColumn get contributionMode =>
      text().map(const InvestmentContributionModeConverter())();

  /// The lump-sum principal for [InvestmentContributionMode.lumpSum], or the
  /// fixed monthly installment for [InvestmentContributionMode.recurring].
  /// Always > 0 (docs/DATA_MODEL.md §46).
  IntColumn get amountMinor => integer()();

  /// ISO 4217 currency code — docs/DATA_MODEL.md §5.
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('BDT'))();

  /// The account contributions are debited from.
  TextColumn get sourceAccountId => text().references(FinancialAccounts, #id)();

  /// The account payouts (periodic profit or maturity proceeds) are credited
  /// to. May be the same account as [sourceAccountId] or a different one.
  TextColumn get payoutAccountId => text().references(FinancialAccounts, #id)();

  /// The calendar date the instrument was opened.
  DateTimeColumn get startDate => dateTime()();

  /// The calendar date the instrument matures. Required — every instrument in
  /// scope is fixed-term.
  DateTimeColumn get maturityDate => dateTime()();

  /// Whether — and how often — this instrument pays profit before maturity.
  TextColumn get payoutFrequency =>
      text().map(const InvestmentPayoutFrequencyConverter())();

  /// The next contribution's due date. Only meaningful for
  /// [InvestmentContributionMode.recurring]; null for a lump-sum instrument,
  /// which has nothing left to contribute after creation.
  DateTimeColumn get nextContributionDue => dateTime().nullable()();

  /// The next payout's due date. Only meaningful when [payoutFrequency] is
  /// periodic (not "at maturity"); null otherwise.
  DateTimeColumn get nextPayoutDue => dateTime().nullable()();

  /// Stored lifecycle state — see `InvestmentStatus`.
  TextColumn get status => text()
      .map(const InvestmentStatusConverter())
      .withDefault(const Constant('ACTIVE'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
