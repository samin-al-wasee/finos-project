import 'package:drift/drift.dart';

/// Drift table for user preferences (docs/UI_DESIGN.md §23).
///
/// Deliberately key-value rather than one typed column per setting: preferences
/// are heterogeneous and will keep accruing (notifications, data options), and a
/// key-value table absorbs each new one without a schema migration. Type safety
/// is restored one layer up by `AppSettings`, which is the only thing that reads
/// these rows.
///
/// This table holds preferences only. It is not a home for financial data —
/// balances, limits, and amounts belong in their own tables where they can be
/// typed and validated.
@DataClassName('PreferenceRow')
class Preferences extends Table {
  /// The setting's stable identifier — see `SettingKeys`.
  TextColumn get key => text()();

  /// The setting's value, serialised as text by the domain layer.
  TextColumn get value => text()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
