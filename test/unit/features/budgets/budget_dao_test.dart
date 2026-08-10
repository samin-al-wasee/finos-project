import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
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
    String categoryId = 'test-food',
    int amountMinor = 1000000,
    BudgetPeriod period = BudgetPeriod.monthly,
    DateTime? startDate,
    DateTime? endDate,
    BudgetStatus status = BudgetStatus.active,
  }) async {
    await dao.insertOne(
      BudgetsCompanion.insert(
        id: id,
        categoryId: categoryId,
        amountMinor: amountMinor,
        period: period,
        startDate: startDate ?? DateTime(2026, 8, 1),
        endDate: Value(endDate),
        status: Value(status),
      ),
    );
  }

  group('insert and read', () {
    test('applies schema defaults', () async {
      await insert('budget-1');

      final row = await dao.getById('budget-1');
      expect(row, isNotNull);
      expect(row!.categoryId, 'test-food');
      expect(row.amountMinor, 1000000);
      expect(row.period, BudgetPeriod.monthly);
      expect(row.currency, 'BDT');
      expect(row.status, BudgetStatus.active);
      expect(row.endDate, isNull);
      expect(row.createdAt, isNotNull);
      expect(row.updatedAt, isNotNull);
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

  group('getActiveFor', () {
    test('finds the active budget for a category and period', () async {
      await insert('budget-1');

      final row = await dao.getActiveFor('test-food', BudgetPeriod.monthly);
      expect(row?.id, 'budget-1');
    });

    test('ignores a different period', () async {
      await insert('budget-1');

      expect(await dao.getActiveFor('test-food', BudgetPeriod.weekly), isNull);
    });

    test('ignores a different category', () async {
      await insert('budget-1');

      expect(
        await dao.getActiveFor('test-transport', BudgetPeriod.monthly),
        isNull,
      );
    });

    test('ignores archived budgets', () async {
      await insert('budget-1', status: BudgetStatus.archived);

      expect(await dao.getActiveFor('test-food', BudgetPeriod.monthly), isNull);
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
