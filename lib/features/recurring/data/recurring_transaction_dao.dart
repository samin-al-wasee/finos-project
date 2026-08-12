import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/recurring_status.dart';
import 'recurring_transaction_table.dart';

part 'recurring_transaction_dao.g.dart';

/// Data-access object for recurring transaction rules (docs/ROADMAP.md §8.1).
@DriftAccessor(tables: [RecurringTransactions])
class RecurringTransactionDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringTransactionDaoMixin {
  RecurringTransactionDao(super.db);

  /// Stream all rules (ordered by name), including archived ones.
  Stream<List<RecurringTransactionRow>> watchAll() {
    return (select(
      recurringTransactions,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  }

  /// One-shot fetch of all rules (ordered by name), including archived ones.
  Future<List<RecurringTransactionRow>> getAll() {
    return (select(
      recurringTransactions,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  /// Get a single rule by ID. Returns `null` if not found.
  Future<RecurringTransactionRow?> getById(String id) {
    return (select(
      recurringTransactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Persists a new rule.
  Future<void> insertOne(RecurringTransactionsCompanion entry) =>
      into(recurringTransactions).insert(entry);

  /// Replaces the entire row for an existing rule.
  ///
  /// `replace` derives the WHERE clause from the row's primary key, so no
  /// explicit condition is needed.
  Future<void> updateOne(RecurringTransactionRow row) =>
      (update(recurringTransactions)).replace(row);

  /// Transitions the lifecycle [status] of the rule identified by [id].
  ///
  /// Throws [StateError] if no rule with that [id] exists.
  Future<void> updateStatus(String id, RecurringStatus status) async {
    final rule = await getById(id);
    if (rule == null) throw StateError('Recurring transaction not found: $id');
    await updateOne(rule.copyWith(status: status, updatedAt: DateTime.now()));
  }

  /// Permanently deletes a rule by [id].
  ///
  /// Never touches a transaction the rule previously generated — nothing
  /// links a transaction back to the rule that created it
  /// (docs/DATA_MODEL.md §56).
  Future<void> deleteOne(String id) async {
    await (delete(recurringTransactions)..where((t) => t.id.equals(id))).go();
  }
}
