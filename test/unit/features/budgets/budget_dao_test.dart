import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_scope.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [BudgetDao] — persistence, lookups, and lifecycle transitions
/// (docs/DATA_MODEL.md §22).
void main() {
  late AppDatabase database;
  late CategoryDao categories;
  late BudgetDao dao;

  setUp(() async {
    database = AppDatabase.inMemory();
    categories = CategoryDao(database);
    dao = BudgetDao(database);

    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-food',
        name: 'Food',
        type: CategoryType.expense,
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-transport',
        name: 'Transport',
        type: CategoryType.expense,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> insert(
    String id, {
    String? categoryId = 'test-food',
    BudgetScopeType scopeType = BudgetScopeType.singleCategory,
    int amountMinor = 1000000,
    BudgetPeriod period = BudgetPeriod.monthly,
    DateTime? startDate,
    DateTime? endDate,
    BudgetStatus status = BudgetStatus.active,
    bool? rolloverEnabled,
  }) async {
    await dao.insertOne(
      BudgetsCompanion.insert(
        id: id,
        categoryId: Value(categoryId),
        scopeType: Value(scopeType),
        amountMinor: amountMinor,
        period: period,
        startDate: startDate ?? DateTime(2026, 8, 1),
        endDate: Value(endDate),
        status: Value(status),
        rolloverEnabled: rolloverEnabled == null
            ? const Value.absent()
            : Value(rolloverEnabled),
      ),
    );
  }

  group('insert and read', () {
    test('applies schema defaults', () async {
      await insert('budget-1');

      final row = await dao.getById('budget-1');
      expect(row, isNotNull);
      expect(row!.categoryId, 'test-food');
      // The column default classifies every budget as SINGLE_CATEGORY unless
      // told otherwise (docs/adr/007-flexible-budget-scope.md).
      expect(row.scopeType, BudgetScopeType.singleCategory);
      expect(row.amountMinor, 1000000);
      expect(row.period, BudgetPeriod.monthly);
      expect(row.currency, 'BDT');
      expect(row.status, BudgetStatus.active);
      expect(row.endDate, isNull);
      expect(row.createdAt, isNotNull);
      expect(row.updatedAt, isNotNull);
      // Off by default (docs/adr/008-budget-rollover.md).
      expect(row.rolloverEnabled, isFalse);
    });

    test('round-trips rolloverEnabled through insert and update', () async {
      await insert('budget-rollover', rolloverEnabled: true);

      final inserted = await dao.getById('budget-rollover');
      expect(inserted!.rolloverEnabled, isTrue);

      await dao.updateOne(inserted.copyWith(rolloverEnabled: false));
      expect((await dao.getById('budget-rollover'))!.rolloverEnabled, isFalse);
    });

    test('accepts a null category for a non-single-category scope', () async {
      await insert(
        'budget-whole',
        categoryId: null,
        scopeType: BudgetScopeType.wholeAccount,
      );

      final row = await dao.getById('budget-whole');
      expect(row!.categoryId, isNull);
      expect(row.scopeType, BudgetScopeType.wholeAccount);
    });

    test('returns null for an unknown id', () async {
      expect(await dao.getById('nope'), isNull);
    });

    test('round-trips every period value', () async {
      for (final period in BudgetPeriod.values) {
        await insert(
          'budget-${period.name}',
          period: period,
          endDate: period == BudgetPeriod.custom ? DateTime(2026, 8, 31) : null,
        );
      }

      final rows = await dao.getAll();
      expect(rows, hasLength(BudgetPeriod.values.length));
      expect(rows.map((r) => r.period).toSet(), BudgetPeriod.values.toSet());
    });

    test('stores a custom period end date', () async {
      await insert(
        'budget-custom',
        period: BudgetPeriod.custom,
        startDate: DateTime(2026, 8, 5),
        endDate: DateTime(2026, 8, 20),
      );

      final row = await dao.getById('budget-custom');
      expect(row!.startDate, DateTime(2026, 8, 5));
      expect(row.endDate, DateTime(2026, 8, 20));
    });

    test('rejects a budget referencing a nonexistent category', () async {
      // Referential integrity (docs/DATA_MODEL.md §44) is enforced by the
      // in-memory database's foreign keys.
      await database.customStatement('PRAGMA foreign_keys = ON');

      expect(
        () => insert('budget-orphan', categoryId: 'cat-missing'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('watchAll', () {
    test('emits budgets oldest first, including archived ones', () async {
      await insert('budget-old', startDate: DateTime(2026, 7, 1));
      await insert(
        'budget-new',
        categoryId: 'test-transport',
        status: BudgetStatus.archived,
      );

      final rows = await dao.watchAll().first;
      expect(rows.map((r) => r.id), ['budget-old', 'budget-new']);
    });
  });

  group('getActiveForPeriod', () {
    test('finds every active budget in the period', () async {
      await insert('budget-1');
      await insert('budget-2', categoryId: 'test-transport');

      final rows = await dao.getActiveForPeriod(BudgetPeriod.monthly);
      expect(rows.map((r) => r.$1.id).toSet(), {'budget-1', 'budget-2'});
    });

    test('ignores a different period', () async {
      await insert('budget-1');

      expect(await dao.getActiveForPeriod(BudgetPeriod.weekly), isEmpty);
    });

    test('ignores archived budgets', () async {
      await insert('budget-1', status: BudgetStatus.archived);

      expect(await dao.getActiveForPeriod(BudgetPeriod.monthly), isEmpty);
    });

    test(
      'pairs a MULTI_CATEGORY budget with its joined category set',
      () async {
        await insert(
          'budget-multi',
          categoryId: null,
          scopeType: BudgetScopeType.multiCategory,
        );
        await dao.setCategoriesFor('budget-multi', {
          'test-food',
          'test-transport',
        });

        final rows = await dao.getActiveForPeriod(BudgetPeriod.monthly);
        expect(rows, hasLength(1));
        expect(rows.single.$2, {'test-food', 'test-transport'});
      },
    );

    test(
      'returns an empty category set for every non-multi-category scope',
      () async {
        await insert('budget-single');
        await insert(
          'budget-uncategorized',
          categoryId: null,
          scopeType: BudgetScopeType.uncategorized,
        );
        await insert(
          'budget-whole',
          categoryId: null,
          scopeType: BudgetScopeType.wholeAccount,
        );

        final rows = await dao.getActiveForPeriod(BudgetPeriod.monthly);
        for (final (_, categoryIds) in rows) {
          expect(categoryIds, isEmpty);
        }
      },
    );
  });

  group('categoriesFor and setCategoriesFor', () {
    test('round-trips a multi-category budget\'s member categories', () async {
      await insert(
        'budget-multi',
        categoryId: null,
        scopeType: BudgetScopeType.multiCategory,
      );

      await dao.setCategoriesFor('budget-multi', {
        'test-food',
        'test-transport',
      });

      expect(await dao.categoriesFor('budget-multi'), {
        'test-food',
        'test-transport',
      });
    });

    test(
      'returns an empty set for a budget with no joined categories',
      () async {
        await insert('budget-single');

        expect(await dao.categoriesFor('budget-single'), isEmpty);
      },
    );

    test('replaces the previous set rather than appending', () async {
      await insert(
        'budget-multi',
        categoryId: null,
        scopeType: BudgetScopeType.multiCategory,
      );
      await dao.setCategoriesFor('budget-multi', {
        'test-food',
        'test-transport',
      });

      await dao.setCategoriesFor('budget-multi', {'test-food'});

      expect(await dao.categoriesFor('budget-multi'), {'test-food'});
    });
  });

  group('update and lifecycle', () {
    test('updateOne replaces the stored row', () async {
      await insert('budget-1');
      final row = await dao.getById('budget-1');

      await dao.updateOne(row!.copyWith(amountMinor: 2000000));

      expect((await dao.getById('budget-1'))!.amountMinor, 2000000);
    });

    test('updateStatus archives and restores', () async {
      await insert('budget-1');

      await dao.updateStatus('budget-1', BudgetStatus.archived);
      expect((await dao.getById('budget-1'))!.status, BudgetStatus.archived);

      await dao.updateStatus('budget-1', BudgetStatus.active);
      expect((await dao.getById('budget-1'))!.status, BudgetStatus.active);
    });

    test('updateStatus throws for an unknown budget', () async {
      expect(
        () => dao.updateStatus('nope', BudgetStatus.archived),
        throwsStateError,
      );
    });

    test('deleteOne removes only the target budget', () async {
      await insert('budget-1');
      await insert('budget-2', categoryId: 'test-transport');

      await dao.deleteOne('budget-1');

      final rows = await dao.getAll();
      expect(rows.map((r) => r.id), ['budget-2']);
    });
  });
}
