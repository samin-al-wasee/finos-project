import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_progress.dart';
import 'package:finos_app/features/budgets/domain/budget_scope.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:finos_app/features/categories/domain/category_origin.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the derived budget figures (docs/DATA_MODEL.md §24–§25).
///
/// ```text
/// Given a Food budget with limit = 10,000
/// When 4,700 of food expenses are recorded
/// Then spent = 4,700 and remaining = 5,300
/// ```
///
/// Health is derived, never stored, so it can never disagree with the
/// transactions it was computed from.
void main() {
  final timestamp = DateTime(2026, 8, 10);

  final category = CategoryRow(
    id: 'cat-food',
    name: 'Food',
    type: CategoryType.expense,
    origin: CategoryOrigin.system,
    icon: 'restaurant',
    status: CategoryStatus.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  final window = DateRange(
    from: DateTime(2026, 8, 1),
    to: DateTime(2026, 9, 1),
  );

  BudgetProgress progressWith({
    required int limitMinor,
    required int spentMinor,
  }) {
    return BudgetProgress(
      budget: BudgetRow(
        id: 'budget-food',
        categoryId: category.id,
        scopeType: BudgetScopeType.singleCategory,
        amountMinor: limitMinor,
        currency: 'BDT',
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 8, 1),
        endDate: null,
        status: BudgetStatus.active,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      scope: SingleCategoryScope(category.id),
      categories: [category],
      window: window,
      spentMinor: spentMinor,
    );
  }

  group('spent and remaining', () {
    test('remaining is the limit minus spending', () {
      // The worked example from docs/DATA_MODEL.md §24, in minor units.
      final progress = progressWith(limitMinor: 1000000, spentMinor: 470000);

      expect(progress.limitMinor, 1000000);
      expect(progress.spentMinor, 470000);
      expect(progress.remainingMinor, 530000);
    });

    test('an untouched budget has its full limit remaining', () {
      final progress = progressWith(limitMinor: 1000000, spentMinor: 0);

      expect(progress.remainingMinor, 1000000);
      expect(progress.usedFraction, 0);
      expect(progress.isExceeded, isFalse);
      expect(progress.health, BudgetHealth.underLimit);
    });

    test('remaining goes negative once the limit is passed', () {
      // Overspending must stay visible rather than clamping to zero, so the UI
      // can report how far over budget the user is.
      final progress = progressWith(limitMinor: 1000000, spentMinor: 1050000);

      expect(progress.remainingMinor, -50000);
      expect(progress.isExceeded, isTrue);
    });
  });

  group('usedFraction', () {
    test('is spending as a fraction of the limit', () {
      expect(
        progressWith(limitMinor: 1000000, spentMinor: 750000).usedFraction,
        0.75,
      );
    });

    test('exceeds 1.0 when over budget rather than clamping', () {
      expect(
        progressWith(limitMinor: 1000000, spentMinor: 1200000).usedFraction,
        1.2,
      );
    });

    test('is zero for a non-positive limit instead of dividing by zero', () {
      // Validation rejects a limit of zero, so this only guards against a
      // corrupted row reaching the UI.
      final progress = progressWith(limitMinor: 0, spentMinor: 5000);

      expect(progress.usedFraction, 0);
    });
  });

  group('health', () {
    test('is under limit below the 80% threshold', () {
      final progress = progressWith(limitMinor: 1000000, spentMinor: 799999);

      expect(progress.health, BudgetHealth.underLimit);
    });

    test('is near limit exactly at the 80% threshold', () {
      final progress = progressWith(limitMinor: 1000000, spentMinor: 800000);

      expect(progress.usedFraction, BudgetProgress.nearLimitThreshold);
      expect(progress.health, BudgetHealth.nearLimit);
    });

    test('is near limit — not exceeded — when spending equals the limit', () {
      // Spending the whole plan is not overspending it.
      final progress = progressWith(limitMinor: 1000000, spentMinor: 1000000);

      expect(progress.remainingMinor, 0);
      expect(progress.isExceeded, isFalse);
      expect(progress.health, BudgetHealth.nearLimit);
    });

    test('is exceeded one minor unit past the limit', () {
      final progress = progressWith(limitMinor: 1000000, spentMinor: 1000001);

      expect(progress.isExceeded, isTrue);
      expect(progress.health, BudgetHealth.exceeded);
    });
  });

  group('scope generalisation (docs/adr/007-flexible-budget-scope.md)', () {
    final transport = CategoryRow(
      id: 'cat-transport',
      name: 'Transport',
      type: CategoryType.expense,
      origin: CategoryOrigin.system,
      icon: 'directions_bus',
      status: CategoryStatus.active,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    BudgetRow budgetRowWith(BudgetScopeType scopeType, {String? categoryId}) {
      return BudgetRow(
        id: 'budget-1',
        categoryId: categoryId,
        scopeType: scopeType,
        amountMinor: 1000000,
        currency: 'BDT',
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 8, 1),
        endDate: null,
        status: BudgetStatus.active,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
    }

    /// Every derived getter behaves identically regardless of [scope] — they
    /// only ever read `budget.amountMinor` and `spentMinor`
    /// (docs/adr/007-flexible-budget-scope.md §4).
    void expectIdenticalDerivedBehavior(BudgetProgress progress) {
      expect(progress.limitMinor, 1000000);
      expect(progress.remainingMinor, 530000);
      expect(progress.usedFraction, closeTo(0.47, 0.0001));
      expect(progress.isExceeded, isFalse);
      expect(progress.health, BudgetHealth.underLimit);
    }

    test('SingleCategoryScope', () {
      expectIdenticalDerivedBehavior(
        BudgetProgress(
          budget: budgetRowWith(
            BudgetScopeType.singleCategory,
            categoryId: category.id,
          ),
          scope: SingleCategoryScope(category.id),
          categories: [category],
          window: window,
          spentMinor: 470000,
        ),
      );
    });

    test('MultiCategoryScope', () {
      expectIdenticalDerivedBehavior(
        BudgetProgress(
          budget: budgetRowWith(BudgetScopeType.multiCategory),
          scope: MultiCategoryScope({category.id, transport.id}),
          categories: [category, transport],
          window: window,
          spentMinor: 470000,
        ),
      );
    });

    test('UncategorizedScope', () {
      expectIdenticalDerivedBehavior(
        BudgetProgress(
          budget: budgetRowWith(BudgetScopeType.uncategorized),
          scope: const UncategorizedScope(),
          categories: const [],
          window: window,
          spentMinor: 470000,
        ),
      );
    });

    test('WholeAccountScope', () {
      expectIdenticalDerivedBehavior(
        BudgetProgress(
          budget: budgetRowWith(BudgetScopeType.wholeAccount),
          scope: const WholeAccountScope(),
          categories: const [],
          window: window,
          spentMinor: 470000,
        ),
      );
    });
  });
}
