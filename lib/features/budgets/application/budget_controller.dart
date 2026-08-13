import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../../categories/data/category_dao.dart';
import '../../categories/domain/category_status.dart';
import '../../categories/domain/category_type.dart';
import '../data/budget_dao.dart';
import '../domain/budget_period.dart';
import '../domain/budget_scope.dart';
import '../domain/budget_status.dart';

/// Application-service for the budget lifecycle (FR-04).
///
/// Sits between the presentation layer and the data layer: it owns business
/// rules (ID generation, validation, which fields an update may change) and
/// keeps screens free of database and domain concerns. Mutations are
/// intentionally non-reactive — screens call these methods and rely on
/// [BudgetDao.watchAll] to refresh automatically.
///
/// Validation follows docs/DATA_MODEL.md §43 and §46:
/// * the limit must be > 0
/// * every category the scope resolves to must exist, be active, and be an
///   expense category
/// * a custom period needs an end date on or after its start date
/// * no two ACTIVE budgets in the same period may have overlapping category
///   scopes (docs/adr/007-flexible-budget-scope.md)
class BudgetController {
  BudgetController(this._dao, this._categories);

  final BudgetDao _dao;
  final CategoryDao _categories;

  /// Creates a new budget with a fresh ULID.
  ///
  /// [scope] is fixed at creation, exactly like a `SINGLE_CATEGORY` budget's
  /// category was fixed before this — there is no way to change it later.
  /// [amountMinor] is the spending limit in integer minor units and must be
  /// positive. [endDate] is required for [BudgetPeriod.custom] and ignored for
  /// the recurring periods, which derive their window from the calendar.
  /// [rolloverEnabled] opts this budget into carrying its unused/overspent
  /// amount into the next period (docs/adr/008-budget-rollover.md); rejected
  /// together with [BudgetPeriod.custom], which has no next period.
  ///
  /// Returns the generated id so callers can navigate to the new budget.
  Future<String> create({
    required BudgetScope scope,
    required int amountMinor,
    required BudgetPeriod period,
    DateTime? startDate,
    DateTime? endDate,
    String currency = 'BDT',
    bool rolloverEnabled = false,
  }) async {
    final start = dayStart(startDate ?? DateTime.now());
    final end = period == BudgetPeriod.custom && endDate != null
        ? dayStart(endDate)
        : null;

    await _validate(
      scope: scope,
      amountMinor: amountMinor,
      period: period,
      startDate: start,
      endDate: end,
      rolloverEnabled: rolloverEnabled,
    );

    final id = generateId();
    final (scopeType, categoryId) = _storedScope(scope);
    await _dao.insertOne(
      BudgetsCompanion.insert(
        id: id,
        categoryId: Value(categoryId),
        scopeType: Value(scopeType),
        amountMinor: amountMinor,
        currency: Value(currency),
        period: period,
        startDate: start,
        endDate: Value(end),
        rolloverEnabled: Value(rolloverEnabled),
      ),
    );
    if (scope is MultiCategoryScope) {
      await _dao.setCategoriesFor(id, scope.categoryIds);
    }
    return id;
  }

  /// Updates the editable fields of the budget identified by [id].
  ///
  /// The category is fixed at creation: changing it would silently reinterpret
  /// every past reading of the budget, so callers archive and recreate instead.
  /// [rolloverEnabled] is not fixed the same way — turning it on or off
  /// doesn't reinterpret any past reading, only whether today's effective
  /// limit includes a derived carry (docs/adr/008-budget-rollover.md).
  /// Touches [BudgetRow.updatedAt]. Throws [StateError] if no such budget exists.
  Future<void> update({
    required String id,
    required int amountMinor,
    required BudgetPeriod period,
    required DateTime startDate,
    DateTime? endDate,
    bool rolloverEnabled = false,
  }) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Budget not found: $id');

    final start = dayStart(startDate);
    final end = period == BudgetPeriod.custom && endDate != null
        ? dayStart(endDate)
        : null;

    await _validate(
      scope: await _resolveStoredScope(row),
      amountMinor: amountMinor,
      period: period,
      startDate: start,
      endDate: end,
      rolloverEnabled: rolloverEnabled,
      ignoreBudgetId: id,
    );

    await _dao.updateOne(
      row.copyWith(
        amountMinor: amountMinor,
        period: period,
        startDate: start,
        endDate: Value(end),
        rolloverEnabled: rolloverEnabled,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Archives a budget (soft-delete), keeping the record for reference.
  ///
  /// Throws [StateError] if the budget doesn't exist.
  Future<void> archive(String id) =>
      _dao.updateStatus(id, BudgetStatus.archived);

  /// Re-activates a previously archived budget.
  ///
  /// Throws [StateError] if the budget doesn't exist, or if an active budget
  /// already has an overlapping scope in the same period
  /// (docs/adr/007-flexible-budget-scope.md).
  Future<void> restore(String id) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Budget not found: $id');

    final scope = await _resolveStoredScope(row);
    final candidates = await _dao.getActiveForPeriod(row.period);
    for (final (existingRow, existingCategoryIds) in candidates) {
      if (existingRow.id == id) continue;
      final existingScope = resolveBudgetScope(
        existingRow,
        existingCategoryIds,
      );
      if (budgetScopesOverlap(scope, existingScope)) {
        throw ArgumentError(
          'An active budget already covers this scope for this period',
        );
      }
    }
    await _dao.updateStatus(id, BudgetStatus.active);
  }

  /// Permanently deletes a budget by [id].
  ///
  /// A budget is a plan rather than a financial fact, so deleting one destroys
  /// no history (docs/DATA_MODEL.md §39).
  Future<void> delete(String id) => _dao.deleteOne(id);

  /// Returns the budget identified by [id], or `null` if not found.
  Future<BudgetRow?> getById(String id) => _dao.getById(id);

  /// Rebuilds the [BudgetScope] a stored [row] represents, fetching its
  /// member categories from the join table when it is `MULTI_CATEGORY`.
  Future<BudgetScope> _resolveStoredScope(BudgetRow row) async {
    final categoryIds = row.scopeType == BudgetScopeType.multiCategory
        ? await _dao.categoriesFor(row.id)
        : const <String>{};
    return resolveBudgetScope(row, categoryIds);
  }

  /// The `(scopeType, categoryId)` pair to persist on the `budgets` row for
  /// [scope]. `categoryId` is non-null only for [SingleCategoryScope]; every
  /// other scope type stores `NULL` there (docs/adr/007-flexible-budget-scope.md).
  (BudgetScopeType, String?) _storedScope(BudgetScope scope) {
    return switch (scope) {
      SingleCategoryScope(:final categoryId) => (
        BudgetScopeType.singleCategory,
        categoryId,
      ),
      MultiCategoryScope() => (BudgetScopeType.multiCategory, null),
      UncategorizedScope() => (BudgetScopeType.uncategorized, null),
      WholeAccountScope() => (BudgetScopeType.wholeAccount, null),
    };
  }

  /// Validates a budget's invariants before persistence.
  ///
  /// Throws [ArgumentError] with a user-readable message when a rule is
  /// violated; throws [StateError] when a referenced category is missing.
  /// [ignoreBudgetId] excludes a budget from the uniqueness check so a budget
  /// can be edited without colliding with itself.
  Future<void> _validate({
    required BudgetScope scope,
    required int amountMinor,
    required BudgetPeriod period,
    required DateTime startDate,
    DateTime? endDate,
    bool rolloverEnabled = false,
    String? ignoreBudgetId,
  }) async {
    if (amountMinor <= 0) {
      throw ArgumentError('Budget limit must be greater than zero');
    }

    // A custom period has no "next period" for anything to carry into
    // (docs/adr/008-budget-rollover.md).
    if (rolloverEnabled && period == BudgetPeriod.custom) {
      throw ArgumentError(
        'Rollover is not available for a custom budget period',
      );
    }

    final categoryIds = switch (scope) {
      SingleCategoryScope(:final categoryId) => [categoryId],
      MultiCategoryScope(:final categoryIds) => categoryIds.toList(),
      UncategorizedScope() => const <String>[],
      WholeAccountScope() => const <String>[],
    };
    if (scope is MultiCategoryScope && categoryIds.length < 2) {
      throw ArgumentError(
        'A multi-category budget needs at least 2 categories',
      );
    }
    for (final categoryId in categoryIds) {
      await _validateCategory(categoryId);
    }

    if (period == BudgetPeriod.custom) {
      if (endDate == null) {
        throw ArgumentError('A custom budget period needs an end date');
      }
      if (endDate.isBefore(startDate)) {
        throw ArgumentError('The end date must be on or after the start date');
      }
    }

    final candidates = await _dao.getActiveForPeriod(period);
    for (final (existingRow, existingCategoryIds) in candidates) {
      if (existingRow.id == ignoreBudgetId) continue;
      final existingScope = resolveBudgetScope(
        existingRow,
        existingCategoryIds,
      );
      if (budgetScopesOverlap(scope, existingScope)) {
        throw ArgumentError(
          'An active budget already covers this scope for this period',
        );
      }
    }
  }

  /// Validates that [categoryId] exists, is active, and is an expense
  /// category — the per-member-category rule every scope type's category set
  /// is checked against.
  Future<void> _validateCategory(String categoryId) async {
    final category = await _categories.getById(categoryId);
    if (category == null) {
      throw StateError('Category not found: $categoryId');
    }
    if (category.status != CategoryStatus.active) {
      throw StateError('Category is not active: ${category.name}');
    }
    // Budgets cap spending, and only expense transactions are spending
    // (docs/DATA_MODEL.md §24), so an income category could never consume one.
    if (category.type != CategoryType.expense) {
      throw ArgumentError(
        'Budgets apply to expense categories; "${category.name}" is an income '
        'category',
      );
    }
  }
}
