import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/budget_period.dart';
import '../domain/budget_scope.dart';
import '../domain/budget_status.dart';
import 'budget_category_table.dart';
import 'budget_table.dart';

part 'budget_dao.g.dart';

/// Data-access object for budgets (docs/DATA_MODEL.md §22–§25).
///
/// Mirrors the [CategoryDao] pattern: streams, one-shot queries, CRUD, and
/// lifecycle status updates. Budget *consumption* is not queried here — that
/// reads the transactions table and lives in
/// [TransactionDao.expenseTotalForCategory] and its scope-generalised
/// siblings, keeping each table's queries in the feature that owns it.
@DriftAccessor(tables: [Budgets, BudgetCategories])
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

  /// Every ACTIVE budget sharing [period], paired with its resolved category
  /// set (docs/adr/007-flexible-budget-scope.md).
  ///
  /// The raw material for the scope-overlap check that replaces the old
  /// category-equality uniqueness rule — no equality comparison happens here,
  /// only fetching. The category set is only ever non-empty for a
  /// `MULTI_CATEGORY` row; every other scope type resolves its own set from
  /// [BudgetRow] alone ([resolveBudgetScope]), so fetching the join table for
  /// them would just return nothing.
  Future<List<(BudgetRow, Set<String>)>> getActiveForPeriod(
    BudgetPeriod period,
  ) async {
    final rows =
        await (select(budgets)..where(
              (t) =>
                  t.period.equalsValue(period) &
                  t.status.equalsValue(BudgetStatus.active),
            ))
            .get();
    return [
      for (final row in rows)
        (
          row,
          row.scopeType == BudgetScopeType.multiCategory
              ? await categoriesFor(row.id)
              : const <String>{},
        ),
    ];
  }

  /// The member categories of a `MULTI_CATEGORY` budget's join-table rows.
  ///
  /// Returns an empty set for any other scope type, since they never have
  /// rows in `budget_categories`.
  Future<Set<String>> categoriesFor(String budgetId) async {
    final rows = await (select(
      budgetCategories,
    )..where((t) => t.budgetId.equals(budgetId))).get();
    return rows.map((r) => r.categoryId).toSet();
  }

  /// Replaces [budgetId]'s member categories with [categoryIds].
  ///
  /// Runs as delete-then-insert inside one batch so the join table never
  /// briefly holds a stale partial set. Only ever called for `MULTI_CATEGORY`
  /// budgets — every other scope type never touches this table.
  Future<void> setCategoriesFor(
    String budgetId,
    Set<String> categoryIds,
  ) async {
    await batch((b) {
      b.deleteWhere(budgetCategories, (t) => t.budgetId.equals(budgetId));
      b.insertAll(budgetCategories, [
        for (final categoryId in categoryIds)
          BudgetCategoriesCompanion.insert(
            budgetId: budgetId,
            categoryId: categoryId,
          ),
      ]);
    });
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
