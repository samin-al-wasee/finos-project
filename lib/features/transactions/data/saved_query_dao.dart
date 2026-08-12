import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'saved_query_table.dart';

part 'saved_query_dao.g.dart';

/// Data-access object for saved transaction filters (docs/ROADMAP.md §8.5).
@DriftAccessor(tables: [SavedQueries])
class SavedQueryDao extends DatabaseAccessor<AppDatabase>
    with _$SavedQueryDaoMixin {
  SavedQueryDao(super.db);

  /// Stream all saved queries, ordered by name.
  Stream<List<SavedQueryRow>> watchAll() {
    return (select(
      savedQueries,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  }

  /// Get a single saved query by ID. Returns `null` if not found.
  Future<SavedQueryRow?> getById(String id) {
    return (select(
      savedQueries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Persists a new saved query row.
  Future<void> insertOne(SavedQueriesCompanion entry) =>
      into(savedQueries).insert(entry);

  /// Permanently deletes a saved query by [id].
  Future<void> deleteOne(String id) async {
    await (delete(savedQueries)..where((t) => t.id.equals(id))).go();
  }
}
