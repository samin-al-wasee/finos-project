import 'package:drift/drift.dart';

import '../../categories/data/category_table.dart';
import '../domain/budget_period.dart';
import '../domain/budget_scope.dart';
import '../domain/budget_status.dart';

/// Drift table for spending budgets (docs/DATA_MODEL.md §22–§25).
///
/// A budget is a *plan*, not a financial fact: it stores a limit for one expense
/// category over a recurring or custom window. Everything about how the budget
/// is performing — spent, remaining, percentage, health — is derived from
/// transactions at read time and is deliberately not stored here
/// (docs/DATA_MODEL.md §45).
///
/// Limits are integer minor units, never binary floating point
/// (docs/DATA_MODEL.md §4).
@DataClassName('BudgetRow')
class Budgets extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  TextColumn get id => text()();

  /// The expense category this budget limits — docs/DATA_MODEL.md §22.
  ///
  /// The foreign key keeps a budget from outliving its category
  /// (docs/DATA_MODEL.md §44); categories are archived rather than deleted, so
  /// an archived category keeps its budget intact.
  ///
  /// Nullable since docs/adr/007-flexible-budget-scope.md: holds the one
  /// category for [BudgetScopeType.singleCategory] exactly as before, and is
  /// `NULL` for the other three scope types (`MULTI_CATEGORY`'s categories
  /// live in `budget_categories`; `UNCATEGORIZED`/`WHOLE_ACCOUNT` have no
  /// single category to store here).
  TextColumn get categoryId => text().nullable().references(Categories, #id)();

  /// What this budget's limit applies to — docs/adr/007-flexible-budget-scope.md.
  ///
  /// Defaults to `SINGLE_CATEGORY` so every budget created before this column
  /// existed is correctly classified the instant it is added, with
  /// [categoryId] untouched.
  TextColumn get scopeType => text()
      .map(const BudgetScopeTypeConverter())
      .withDefault(const Constant('SINGLE_CATEGORY'))();

  /// The spending limit in integer minor units; always > 0
  /// (docs/DATA_MODEL.md §46).
  IntColumn get amountMinor => integer()();

  /// ISO 4217 currency code — docs/DATA_MODEL.md §5.
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('BDT'))();

  /// Recurrence shape of the window — docs/DATA_MODEL.md §23.
  TextColumn get period => text().map(const BudgetPeriodConverter())();

  /// The calendar date the budget takes effect.
  ///
  /// For [BudgetPeriod.custom] this is also the authoritative window start; the
  /// recurring periods derive their window from the calendar instead, so a
  /// monthly budget means "this calendar month" regardless of the day it was
  /// created on.
  DateTimeColumn get startDate => dateTime()();

  /// Inclusive last day of the window. Required for [BudgetPeriod.custom] and
  /// null for the recurring periods, which never end.
  DateTimeColumn get endDate => dateTime().nullable()();

  /// Lifecycle state — docs/DATA_MODEL.md §22, §39.
  TextColumn get status => text()
      .map(const BudgetStatusConverter())
      .withDefault(const Constant('ACTIVE'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
