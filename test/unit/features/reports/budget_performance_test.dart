import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_progress.dart';
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
        amountMinor: limitMinor,
        currency: 'BDT',
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 8, 1),
        endDate: null,
        status: status,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      category: category,
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
}
