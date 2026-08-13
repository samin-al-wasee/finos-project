import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// What a budget's limit applies to (docs/DATA_MODEL.md §22,
/// docs/adr/007-flexible-budget-scope.md).
///
/// Generalises the V1 "exactly one category" rule into four shapes:
///
/// * [SingleCategoryScope] — today's behavior, one category.
/// * [MultiCategoryScope] — a limit shared across a set of categories
///   (≥ 2, enforced by validation).
/// * [UncategorizedScope] — a catch-all for expenses with no category.
/// * [WholeAccountScope] — every expense, regardless of category.
///
/// A budget's scope is fixed at creation, exactly like a `SINGLE_CATEGORY`
/// budget's category is fixed today (§22).
sealed class BudgetScope {
  const BudgetScope();
}

/// Applies to exactly one category — the only scope V1 supported.
class SingleCategoryScope extends BudgetScope {
  const SingleCategoryScope(this.categoryId);

  final String categoryId;
}

/// Applies to a set of two or more categories, sharing one limit.
class MultiCategoryScope extends BudgetScope {
  const MultiCategoryScope(this.categoryIds);

  /// Length is always >= 2 — enforced by [BudgetController] validation, not
  /// by this type.
  final Set<String> categoryIds;
}

/// Applies only to expenses with no category (`category_id IS NULL`).
class UncategorizedScope extends BudgetScope {
  const UncategorizedScope();
}

/// Applies to every expense, regardless of category.
class WholeAccountScope extends BudgetScope {
  const WholeAccountScope();
}

/// Maps [BudgetScopeType] to its canonical uppercase storage value in the
/// database (`SINGLE_CATEGORY`, `MULTI_CATEGORY`, `UNCATEGORIZED`,
/// `WHOLE_ACCOUNT`), mirroring [BudgetPeriodConverter]'s exact shape.
enum BudgetScopeType {
  singleCategory,
  multiCategory,
  uncategorized,
  wholeAccount,
}

/// Maps [BudgetScopeType] to its canonical uppercase storage value in the
/// database, mirroring `BudgetPeriodConverter`'s exact shape.
class BudgetScopeTypeConverter extends TypeConverter<BudgetScopeType, String> {
  const BudgetScopeTypeConverter();

  static const Map<BudgetScopeType, String> _storage = {
    BudgetScopeType.singleCategory: 'SINGLE_CATEGORY',
    BudgetScopeType.multiCategory: 'MULTI_CATEGORY',
    BudgetScopeType.uncategorized: 'UNCATEGORIZED',
    BudgetScopeType.wholeAccount: 'WHOLE_ACCOUNT',
  };

  @override
  BudgetScopeType fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError('Unknown BudgetScopeType storage value: $fromDb');
  }

  @override
  String toSql(BudgetScopeType value) => _storage[value]!;
}

/// Builds the [BudgetScope] a stored [budget] row represents.
///
/// [joinedCategoryIds] is the budget's rows in `budget_categories`
/// (`BudgetDao.categoriesFor`) — only meaningful, and only ever non-empty,
/// for [BudgetScopeType.multiCategory].
BudgetScope resolveBudgetScope(
  BudgetRow budget,
  Set<String> joinedCategoryIds,
) {
  switch (budget.scopeType) {
    case BudgetScopeType.singleCategory:
      return SingleCategoryScope(budget.categoryId!);
    case BudgetScopeType.multiCategory:
      return MultiCategoryScope(joinedCategoryIds);
    case BudgetScopeType.uncategorized:
      return const UncategorizedScope();
    case BudgetScopeType.wholeAccount:
      return const WholeAccountScope();
  }
}

/// Whether two budgets' category scopes could both match the same expense
/// (docs/ROADMAP.md §8.3). This is the generalisation of "same category" that
/// replaces `BudgetDao.getActiveFor`'s equality check; it is what makes a
/// [WholeAccountScope] collide with everything, an [UncategorizedScope]
/// collide only with itself and [WholeAccountScope], and two category sets
/// collide exactly when they intersect.
bool budgetScopesOverlap(BudgetScope a, BudgetScope b) {
  if (a is WholeAccountScope || b is WholeAccountScope) return true;
  if (a is UncategorizedScope || b is UncategorizedScope) {
    return a is UncategorizedScope && b is UncategorizedScope;
  }
  final aIds = a is SingleCategoryScope
      ? {a.categoryId}
      : (a as MultiCategoryScope).categoryIds;
  final bIds = b is SingleCategoryScope
      ? {b.categoryId}
      : (b as MultiCategoryScope).categoryIds;
  return aIds.intersection(bIds).isNotEmpty;
}

/// Whether [row] falls inside [scope]'s categories.
///
/// A pure per-row predicate, the same shape as `TransactionFilter.matches`
/// for accounts — callers still need to check `row.type ==
/// TransactionType.expense` and the budget's current window themselves,
/// since scope alone doesn't decide either of those (docs/DATA_MODEL.md §25:
/// "income and transfers are excluded").
bool budgetScopeMatches(BudgetScope scope, TransactionRow row) {
  return switch (scope) {
    SingleCategoryScope(:final categoryId) => row.categoryId == categoryId,
    MultiCategoryScope(:final categoryIds) =>
      row.categoryId != null && categoryIds.contains(row.categoryId),
    UncategorizedScope() => row.categoryId == null,
    WholeAccountScope() => true,
  };
}
