import 'package:drift/drift.dart';

/// Drift table for saved transaction filters (docs/ROADMAP.md §8.5, "saved
/// query/report builder").
///
/// `filterJson` stores [TransactionFilter.toJson] — the structured criteria
/// only, never the free-text search box (see that method's doc comment).
@DataClassName('SavedQueryRow')
class SavedQueries extends Table {
  /// Stable, globally unique identifier (UUID/ULID) — docs/DATA_MODEL.md §3.
  TextColumn get id => text()();

  /// Label shown in the saved-filters list, e.g. "Food over ৳500".
  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// JSON-encoded [TransactionFilter.toJson].
  TextColumn get filterJson => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
