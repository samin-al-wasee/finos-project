import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_progress.dart';
import 'package:finos_app/features/budgets/domain/budget_scope.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:finos_app/features/categories/domain/category_origin.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/reports/domain/budget_performance.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [budgetsForPerformanceReport] (docs/ROADMAP.md §8.4).
void main() {
  final timestamp = DateTime(2026, 8, 10);
  final window = DateRange(
    from: DateTime(2026, 8, 1),
    to: DateTime(2026, 9, 1),
  );

  CategoryRow categoryWith(String id) => CategoryRow(
    id: id,
    name: id,
    type: CategoryType.expense,
    origin: CategoryOrigin.system,
    icon: 'label',
    status: CategoryStatus.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  BudgetProgress progressWith({
    required String id,
    required int limitMinor,
    required int spentMinor,
    BudgetStatus status = BudgetStatus.active,
  }) {
    final category = categoryWith('cat-$id');
    return BudgetProgress(
      budget: BudgetRow(
        id: id,
        categoryId: category.id,
        scopeType: BudgetScopeType.singleCategory,
        amountMinor: limitMinor,
        currency: 'BDT',
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 8, 1),
        endDate: null,
        status: status,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      scope: SingleCategoryScope(category.id),
      categories: [category],
      window: window,
      spentMinor: spentMinor,
    );
  }

  /// A budget built from a non-[SingleCategoryScope] scope, to prove the
  /// sort/aggregate logic never touches `.category`/`.categories`
  /// (docs/adr/007-flexible-budget-scope.md).
  BudgetProgress wholeAccountProgressWith({
    required String id,
    required int limitMinor,
    required int spentMinor,
  }) {
    return BudgetProgress(
      budget: BudgetRow(
        id: id,
        categoryId: null,
        scopeType: BudgetScopeType.wholeAccount,
        amountMinor: limitMinor,
        currency: 'BDT',
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 8, 1),
        endDate: null,
        status: BudgetStatus.active,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      scope: const WholeAccountScope(),
      categories: const [],
      window: window,
      spentMinor: spentMinor,
    );
  }

  test('excludes archived budgets', () {
    final active = progressWith(id: 'active', limitMinor: 1000, spentMinor: 0);
    final archived = progressWith(
      id: 'archived',
      limitMinor: 1000,
      spentMinor: 0,
      status: BudgetStatus.archived,
    );

    final result = budgetsForPerformanceReport([active, archived]);

    expect(result, [active]);
  });

  test('sorts exceeded before near-limit before under-limit', () {
    final underLimit = progressWith(
      id: 'under',
      limitMinor: 1000,
      spentMinor: 100,
    );
    final exceeded = progressWith(
      id: 'exceeded',
      limitMinor: 1000,
      spentMinor: 1200,
    );
    final nearLimit = progressWith(
      id: 'near',
      limitMinor: 1000,
      spentMinor: 850,
    );

    final result = budgetsForPerformanceReport([
      underLimit,
      exceeded,
      nearLimit,
    ]);

    expect(result.map((p) => p.budget.id), ['exceeded', 'near', 'under']);
  });

  test('breaks ties within a health group by higher used fraction first', () {
    final lessUsed = progressWith(id: 'less', limitMinor: 1000, spentMinor: 0);
    final moreUsed = progressWith(
      id: 'more',
      limitMinor: 1000,
      spentMinor: 500,
    );

    final result = budgetsForPerformanceReport([lessUsed, moreUsed]);

    expect(result.map((p) => p.budget.id), ['more', 'less']);
  });

  test(
    'sorts a non-SingleCategoryScope budget by health/usedFraction alone',
    () {
      // Proves the sort/aggregate logic never touches
      // `.category`/`.categories` (docs/adr/007-flexible-budget-scope.md) —
      // only `.health`/`.usedFraction`/`.budget.status`, which are unchanged
      // regardless of scope.
      final wholeAccount = wholeAccountProgressWith(
        id: 'whole',
        limitMinor: 1000,
        spentMinor: 1200,
      );
      final underLimit = progressWith(
        id: 'under',
        limitMinor: 1000,
        spentMinor: 100,
      );

      final result = budgetsForPerformanceReport([underLimit, wholeAccount]);

      expect(result.map((p) => p.budget.id), ['whole', 'under']);
    },
  );
}
