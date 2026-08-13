import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_scope.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [budgetScopesOverlap] and [resolveBudgetScope]
/// (docs/adr/007-flexible-budget-scope.md, docs/ROADMAP.md §8.3).
///
/// This is the generalisation of the V1 "same category" equality check into a
/// set-overlap rule; every pairwise combination of the four scope types is
/// exercised here, pure and without a database.
void main() {
  group('budgetScopesOverlap', () {
    group('SingleCategoryScope vs SingleCategoryScope', () {
      test('overlaps when the category is the same', () {
        expect(
          budgetScopesOverlap(
            const SingleCategoryScope('food'),
            const SingleCategoryScope('food'),
          ),
          isTrue,
        );
      });

      test('does not overlap when the category differs', () {
        expect(
          budgetScopesOverlap(
            const SingleCategoryScope('food'),
            const SingleCategoryScope('transport'),
          ),
          isFalse,
        );
      });
    });

    group('MultiCategoryScope vs SingleCategoryScope', () {
      test('overlaps when they share one category', () {
        // The resolved edge case from ADR-007 §1: a category cannot belong to
        // a multi-category budget while also carrying its own
        // single-category budget in the same period.
        expect(
          budgetScopesOverlap(
            const MultiCategoryScope({'food', 'entertainment'}),
            const SingleCategoryScope('food'),
          ),
          isTrue,
        );
        expect(
          budgetScopesOverlap(
            const SingleCategoryScope('food'),
            const MultiCategoryScope({'food', 'entertainment'}),
          ),
          isTrue,
        );
      });

      test('does not overlap when disjoint', () {
        expect(
          budgetScopesOverlap(
            const MultiCategoryScope({'dining', 'entertainment'}),
            const SingleCategoryScope('transport'),
          ),
          isFalse,
        );
      });
    });

    group('MultiCategoryScope vs MultiCategoryScope', () {
      test('overlaps when the sets intersect', () {
        expect(
          budgetScopesOverlap(
            const MultiCategoryScope({'dining', 'entertainment'}),
            const MultiCategoryScope({'entertainment', 'travel'}),
          ),
          isTrue,
        );
      });

      test('does not overlap when the sets are disjoint', () {
        expect(
          budgetScopesOverlap(
            const MultiCategoryScope({'dining', 'entertainment'}),
            const MultiCategoryScope({'transport', 'travel'}),
          ),
          isFalse,
        );
      });
    });

    group('UncategorizedScope', () {
      test('overlaps with itself', () {
        expect(
          budgetScopesOverlap(
            const UncategorizedScope(),
            const UncategorizedScope(),
          ),
          isTrue,
        );
      });

      test('does not overlap with a single category', () {
        expect(
          budgetScopesOverlap(
            const UncategorizedScope(),
            const SingleCategoryScope('food'),
          ),
          isFalse,
        );
        expect(
          budgetScopesOverlap(
            const SingleCategoryScope('food'),
            const UncategorizedScope(),
          ),
          isFalse,
        );
      });

      test('does not overlap with a multi-category scope', () {
        expect(
          budgetScopesOverlap(
            const UncategorizedScope(),
            const MultiCategoryScope({'dining', 'entertainment'}),
          ),
          isFalse,
        );
      });

      test('overlaps with whole account', () {
        expect(
          budgetScopesOverlap(
            const UncategorizedScope(),
            const WholeAccountScope(),
          ),
          isTrue,
        );
      });
    });

    group('WholeAccountScope', () {
      test('overlaps with itself', () {
        expect(
          budgetScopesOverlap(
            const WholeAccountScope(),
            const WholeAccountScope(),
          ),
          isTrue,
        );
      });

      test('overlaps with a single category', () {
        expect(
          budgetScopesOverlap(
            const WholeAccountScope(),
            const SingleCategoryScope('food'),
          ),
          isTrue,
        );
      });

      test('overlaps with a multi-category scope', () {
        expect(
          budgetScopesOverlap(
            const WholeAccountScope(),
            const MultiCategoryScope({'dining', 'entertainment'}),
          ),
          isTrue,
        );
      });

      test('overlaps with uncategorized', () {
        expect(
          budgetScopesOverlap(
            const WholeAccountScope(),
            const UncategorizedScope(),
          ),
          isTrue,
        );
      });
    });
  });

  group('BudgetScopeTypeConverter', () {
    test('round-trips every value through its storage string', () {
      const converter = BudgetScopeTypeConverter();
      for (final type in BudgetScopeType.values) {
        expect(converter.fromSql(converter.toSql(type)), type);
      }
    });

    test('uses the canonical uppercase storage values', () {
      const converter = BudgetScopeTypeConverter();
      expect(
        converter.toSql(BudgetScopeType.singleCategory),
        'SINGLE_CATEGORY',
      );
      expect(converter.toSql(BudgetScopeType.multiCategory), 'MULTI_CATEGORY');
      expect(converter.toSql(BudgetScopeType.uncategorized), 'UNCATEGORIZED');
      expect(converter.toSql(BudgetScopeType.wholeAccount), 'WHOLE_ACCOUNT');
    });

    test('throws for an unrecognised storage value', () {
      expect(
        () => const BudgetScopeTypeConverter().fromSql('NOPE'),
        throwsArgumentError,
      );
    });
  });

  group('resolveBudgetScope', () {
    final timestamp = DateTime(2026, 8, 10);

    BudgetRow rowWith({
      required BudgetScopeType scopeType,
      String? categoryId,
    }) {
      return BudgetRow(
        id: 'budget-1',
        categoryId: categoryId,
        scopeType: scopeType,
        amountMinor: 1000000,
        currency: 'BDT',
        period: BudgetPeriod.monthly,
        startDate: timestamp,
        endDate: null,
        status: BudgetStatus.active,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
    }

    test('resolves a single-category row', () {
      final scope = resolveBudgetScope(
        rowWith(scopeType: BudgetScopeType.singleCategory, categoryId: 'food'),
        const {},
      );
      expect(scope, isA<SingleCategoryScope>());
      expect((scope as SingleCategoryScope).categoryId, 'food');
    });

    test('resolves a multi-category row from its joined category ids', () {
      final scope = resolveBudgetScope(
        rowWith(scopeType: BudgetScopeType.multiCategory),
        {'dining', 'entertainment'},
      );
      expect(scope, isA<MultiCategoryScope>());
      expect((scope as MultiCategoryScope).categoryIds, {
        'dining',
        'entertainment',
      });
    });

    test('resolves an uncategorized row regardless of joined ids', () {
      final scope = resolveBudgetScope(
        rowWith(scopeType: BudgetScopeType.uncategorized),
        const {},
      );
      expect(scope, isA<UncategorizedScope>());
    });

    test('resolves a whole-account row regardless of joined ids', () {
      final scope = resolveBudgetScope(
        rowWith(scopeType: BudgetScopeType.wholeAccount),
        const {},
      );
      expect(scope, isA<WholeAccountScope>());
    });
  });
}
