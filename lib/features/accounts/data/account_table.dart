import 'package:drift/drift.dart';

import '../domain/account_status.dart';
import '../domain/account_type.dart';

/// Drift table for financial accounts (docs/DATA_MODEL.md §6–§10).
///
/// Amounts are stored as integer minor units (never binary floating point) per
/// docs/DATA_MODEL.md §4. The currency implies the decimal scale.
@DataClassName('FinancialAccountRow')
class FinancialAccounts extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  TextColumn get id => text()();

  /// User-facing account name.
  TextColumn get name => text()();

  /// Account type (bank, mfs, credit card, ...) — docs/DATA_MODEL.md §7.
  TextColumn get type => text().map(const AccountTypeConverter())();

  /// ISO 4217 currency code — docs/DATA_MODEL.md §5.
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('BDT'))();

  /// Opening balance in integer minor units — docs/DATA_MODEL.md §9.
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Account lifecycle state — docs/DATA_MODEL.md §8.
  TextColumn get status => text()
      .map(const AccountStatusConverter())
      .withDefault(const Constant('ACTIVE'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
