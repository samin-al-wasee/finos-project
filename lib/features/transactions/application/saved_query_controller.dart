import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../data/saved_query_dao.dart';
import '../domain/transaction_filter.dart';

/// Application service for the saved-query lifecycle (docs/ROADMAP.md §8.5).
///
/// A saved query is a named, reusable set of structured filter criteria — it
/// never touches a transaction, an account balance, or a budget.
class SavedQueryController {
  SavedQueryController(this._dao);

  final SavedQueryDao _dao;

  /// Saves [filter]'s structured criteria under [name].
  ///
  /// Returns the generated ID.
  ///
  /// Throws [ArgumentError] for an empty name or a filter with no criteria
  /// set — saving "everything" isn't a meaningful query to reapply later.
  Future<String> save({
    required String name,
    required TransactionFilter filter,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Enter a name for this saved filter');
    }
    if (!filter.isActive) {
      throw ArgumentError('Set at least one filter before saving');
    }

    final id = generateId();
    await _dao.insertOne(
      SavedQueriesCompanion.insert(
        id: id,
        name: trimmedName,
        filterJson: jsonEncode(filter.toJson()),
      ),
    );
    return id;
  }

  /// Decodes [row]'s stored criteria back into a [TransactionFilter].
  TransactionFilter filterFor(SavedQueryRow row) => TransactionFilter.fromJson(
    jsonDecode(row.filterJson) as Map<String, dynamic>,
  );

  /// Permanently deletes a saved query.
  Future<void> delete(String id) => _dao.deleteOne(id);
}
