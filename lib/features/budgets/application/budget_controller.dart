import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../../categories/data/category_dao.dart';
import '../../categories/domain/category_status.dart';
import '../../categories/domain/category_type.dart';
import '../data/budget_dao.dart';
import '../domain/budget_period.dart';
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
/// * the category must exist, be active, and be an expense category
/// * a custom period needs an end date on or after its start date
/// * only one ACTIVE budget may exist per category and period
class BudgetController {
  BudgetController(this._dao, this._categories);

  final BudgetDao _dao;
  final CategoryDao _categories;

  /// Creates a new budget with a fresh ULID.
  ///
  /// [amountMinor] is the spending limit in integer minor units and must be
  /// positive. [endDate] is required for [BudgetPeriod.custom] and ignored for
  /// the recurring periods, which derive their window from the calendar.
  ///
  /// Returns the generated id so callers can navigate to the new budget.
  Future<String> create({
    required String categoryId,
    required int amountMinor,
    required BudgetPeriod period,
    DateTime? startDate,
    DateTime? endDate,
    String currency = 'BDT',
  }) async {
    final start = dayStart(startDate ?? DateTime.now());
    final end = period == BudgetPeriod.custom && endDate != null
        ? dayStart(endDate)
        : null;

    await _validate(
      categoryId: categoryId,
      amountMinor: amountMinor,
      period: period,
      startDate: start,
      endDate: end,
    );

    final id = generateId();
    await _dao.insertOne(
      BudgetsCompanion.insert(
        id: id,
        categoryId: categoryId,
        amountMinor: amountMinor,
        currency: Value(currency),
        period: period,
        startDate: start,
        endDate: Value(end),
      ),
    );
    return id;
  }

  /// Updates the editable fields of the budget identified by [id].
  ///
  /// The category is fixed at creation: changing it would silently reinterpret
  /// every past reading of the budget, so callers archive and recreate instead.
  /// Touches [BudgetRow.updatedAt]. Throws [StateError] if no such budget exists.
  Future<void> update({
    required String id,
    required int amountMinor,
    required BudgetPeriod period,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Budget not found: $id');

    final start = dayStart(startDate);
    final end = period == BudgetPeriod.custom && endDate != null
        ? dayStart(endDate)
        : null;

    await _validate(
      categoryId: row.categoryId,
      amountMinor: amountMinor,
      period: period,
      startDate: start,
      endDate: end,
      ignoreBudgetId: id,
    );

    await _dao.updateOne(
      row.copyWith(
        amountMinor: amountMinor,
        period: period,
        startDate: start,
        endDate: Value(end),
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
  /// already covers the same category and period.
  Future<void> restore(String id) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Budget not found: $id');

    final existing = await _dao.getActiveFor(row.categoryId, row.period);
    if (existing != null && existing.id != id) {
      throw ArgumentError(
        'An active budget already covers this category and period',
      );
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

  /// Validates a budget's invariants before persistence.
  ///
  /// Throws [ArgumentError] with a user-readable message when a rule is
  /// violated; throws [StateError] when the referenced category is missing.
  /// [ignoreBudgetId] excludes a budget from the uniqueness check so a budget
  /// can be edited without colliding with itself.
  Future<void> _validate({
    required String categoryId,
    required int amountMinor,
    required BudgetPeriod period,
    required DateTime startDate,
    DateTime? endDate,
    String? ignoreBudgetId,
  }) async {
    if (amountMinor <= 0) {
      throw ArgumentError('Budget limit must be greater than zero');
    }

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

    if (period == BudgetPeriod.custom) {
      if (endDate == null) {
        throw ArgumentError('A custom budget period needs an end date');
      }
      if (endDate.isBefore(startDate)) {
        throw ArgumentError('The end date must be on or after the start date');
      }
    }

    final existing = await _dao.getActiveFor(categoryId, period);
    if (existing != null && existing.id != ignoreBudgetId) {
      throw ArgumentError(
        'An active budget already covers this category and period',
      );
    }
  }
}
