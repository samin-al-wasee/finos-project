import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/budget_period.dart';
import '../domain/budget_status.dart';
import 'budget_table.dart';

part 'budget_dao.g.dart';

/// Data-access object for budgets (docs/DATA_MODEL.md §22–§25).
///
/// Mirrors the [CategoryDao] pattern: streams, one-shot queries, CRUD, and
/// lifecycle status updates. Budget *consumption* is not queried here — that
/// reads the transactions table and lives in
/// [TransactionDao.expenseTotalForCategory], keeping each table's queries in the
/// feature that owns it.
@DriftAccessor(tables: [Budgets])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  /// Stream all budgets, oldest first, including archived ones.
  ///
  /// Archived budgets are included so the management screen can group them in an
  /// "Archived" section and offer a restore action (docs/DATA_MODEL.md §39).
  Stream<List<BudgetRow>> watchAll() => (select(
    budgets,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();

  /// One-shot fetch of all budgets, oldest first, including archived ones.
  Future<List<BudgetRow>> getAll() =>
      (select(budgets)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  /// Returns a single budget by its [id], or `null` if not found.
  Future<BudgetRow?> getById(String id) =>
      (select(budgets)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Returns the ACTIVE budget for [categoryId] with the given [period], or
  /// `null` if there is none.
  ///
  /// Used to enforce one active budget per category and period so that spending
  /// can never be attributed to two competing limits at once.
  Future<BudgetRow?> getActiveFor(String categoryId, BudgetPeriod period) {
    return (select(budgets)..where(
          (t) =>
              t.categoryId.equals(categoryId) &
              t.period.equalsValue(period) &
              t.status.equalsValue(BudgetStatus.active),
        ))
        .getSingleOrNull();
  }

  /// Persists a new budget row.
  Future<void> insertOne(BudgetsCompanion entry) => into(budgets).insert(entry);

  /// Replaces the entire row for an existing budget.
  ///
  /// `replace` derives the WHERE clause from the row's primary key, so no
  /// explicit condition is needed.
  Future<void> updateOne(BudgetRow row) => (update(budgets)).replace(row);

  /// Permanently deletes a budget by [id].
  ///
  /// Safe to hard-delete: a budget is a forward-looking plan, so removing one
  /// destroys no financial history (docs/DATA_MODEL.md §39). Users who want to
  /// keep the record can archive instead.
  Future<void> deleteOne(String id) async {
    await (delete(budgets)..where((t) => t.id.equals(id))).go();
  }

  /// Transitions the lifecycle [status] of the budget identified by [id].
  ///
  /// Throws [StateError] if no budget with that [id] exists.
  Future<void> updateStatus(String id, BudgetStatus status) async {
    final budget = await getById(id);
    if (budget == null) throw StateError('Budget not found: $id');
    await updateOne(budget.copyWith(status: status, updatedAt: DateTime.now()));
  }
}
