import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/savings_goal_status.dart';
import 'savings_goal_table.dart';

part 'savings_goal_dao.g.dart';

/// Data-access object for savings goals (docs/adr/011-savings-goals.md).
///
/// Only the goal record lives here. Contributions and withdrawals are
/// transactions, so the money and everything derived from it is queried
/// through `TransactionDao`, the same split `LoanDao`/`InvestmentDao` use.
@DriftAccessor(tables: [SavingsGoals])
class SavingsGoalDao extends DatabaseAccessor<AppDatabase>
    with _$SavingsGoalDaoMixin {
  SavingsGoalDao(super.db);

  /// Stream all savings goals, newest first, including archived ones.
  Stream<List<SavingsGoalRow>> watchAll() => (select(
    savingsGoals,
  )..orderBy([(t) => OrderingTerm.desc(t.startDate)])).watch();

  /// One-shot fetch of all savings goals, newest first, including archived
  /// ones.
  Future<List<SavingsGoalRow>> getAll() => (select(
    savingsGoals,
  )..orderBy([(t) => OrderingTerm.desc(t.startDate)])).get();

  /// Returns a single savings goal by its [id], or `null` if not found.
  Future<SavingsGoalRow?> getById(String id) =>
      (select(savingsGoals)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Persists a new savings goal row.
  Future<void> insertOne(SavingsGoalsCompanion entry) =>
      into(savingsGoals).insert(entry);

  /// Replaces the entire row for an existing savings goal.
  Future<void> updateOne(SavingsGoalRow row) =>
      (update(savingsGoals)).replace(row);

  /// Permanently deletes a savings goal by [id].
  ///
  /// The caller must remove the goal's transactions in the same database
  /// transaction; the foreign key on `transactions.savings_goal_id`
  /// otherwise blocks this.
  Future<void> deleteOne(String id) async {
    await (delete(savingsGoals)..where((t) => t.id.equals(id))).go();
  }

  /// Transitions the lifecycle [status] of the savings goal identified by
  /// [id].
  ///
  /// Throws [StateError] if no goal with that [id] exists.
  Future<void> updateStatus(String id, SavingsGoalStatus status) async {
    final goal = await getById(id);
    if (goal == null) throw StateError('Savings goal not found: $id');
    await updateOne(goal.copyWith(status: status, updatedAt: DateTime.now()));
  }
}
