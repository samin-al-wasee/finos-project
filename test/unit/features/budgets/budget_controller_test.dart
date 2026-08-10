import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/budgets/application/budget_controller.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [BudgetController] — the budget validation rules
/// (docs/DATA_MODEL.md §43, §46 and FR-04).
void main() {
  late AppDatabase database;
  late CategoryDao categories;
  late BudgetDao dao;
  late BudgetController controller;

  setUp(() async {
    database = AppDatabase.inMemory();
    categories = CategoryDao(database);
    dao = BudgetDao(database);
    controller = BudgetController(dao, categories);

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
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-salary',
        name: 'Salary',
        type: CategoryType.income,
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'test-archived',
        name: 'Old Habit',
        type: CategoryType.expense,
        status: Value(CategoryStatus.archived),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('create', () {
    test('persists a budget and returns its generated id', () async {
      final id = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 8, 10, 14, 30),
      );

      expect(id, isNotEmpty);
      final row = await dao.getById(id);
      expect(row, isNotNull);
      expect(row!.categoryId, 'test-food');
      expect(row.amountMinor, 1000000);
      expect(row.period, BudgetPeriod.monthly);
      expect(row.status, BudgetStatus.active);
      // The start date is normalised to a calendar date
      // (docs/DATA_MODEL.md §42).
      expect(row.startDate, DateTime(2026, 8, 10));
    });

    test('defaults the start date to today', () async {
      final id = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
      );

      final now = DateTime.now();
      expect(
        (await dao.getById(id))!.startDate,
        DateTime(now.year, now.month, now.day),
      );
    });

    test('rejects a zero limit', () async {
      expect(
        () => controller.create(
          categoryId: 'test-food',
          amountMinor: 0,
          period: BudgetPeriod.monthly,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a negative limit', () async {
      expect(
        () => controller.create(
          categoryId: 'test-food',
          amountMinor: -5000,
          period: BudgetPeriod.monthly,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a missing category', () async {
      expect(
        () => controller.create(
          categoryId: 'cat-missing',
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
        ),
        throwsStateError,
      );
    });

    test('rejects an archived category', () async {
      expect(
        () => controller.create(
          categoryId: 'test-archived',
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
        ),
        throwsStateError,
      );
    });

    test('rejects an income category', () async {
      // Only expenses consume a budget (docs/DATA_MODEL.md §24), so an income
      // category could never be measured against a limit.
      expect(
        () => controller.create(
          categoryId: 'test-salary',
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a custom period without an end date', () async {
      expect(
        () => controller.create(
          categoryId: 'test-food',
          amountMinor: 1000000,
          period: BudgetPeriod.custom,
          startDate: DateTime(2026, 8, 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a custom period ending before it starts', () async {
      expect(
        () => controller.create(
          categoryId: 'test-food',
          amountMinor: 1000000,
          period: BudgetPeriod.custom,
          startDate: DateTime(2026, 8, 20),
          endDate: DateTime(2026, 8, 5),
        ),
        throwsArgumentError,
      );
    });

    test('accepts a single-day custom period', () async {
      final id = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.custom,
        startDate: DateTime(2026, 8, 10),
        endDate: DateTime(2026, 8, 10),
      );

      final row = await dao.getById(id);
      expect(row!.endDate, DateTime(2026, 8, 10));
    });

    test('drops an end date on a recurring period', () async {
      // Recurring windows come from the calendar, so a stray end date must not
      // be persisted where it would be silently ignored.
      final id = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
        endDate: DateTime(2026, 8, 31),
      );

      expect((await dao.getById(id))!.endDate, isNull);
    });
  });

  group('one active budget per category and period', () {
    test('rejects a duplicate active budget', () async {
      await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
      );

      expect(
        () => controller.create(
          categoryId: 'test-food',
          amountMinor: 2000000,
          period: BudgetPeriod.monthly,
        ),
        throwsArgumentError,
      );
    });

    test('allows the same category with a different period', () async {
      await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
      );
      await controller.create(
        categoryId: 'test-food',
        amountMinor: 250000,
        period: BudgetPeriod.weekly,
      );

      expect(await dao.getAll(), hasLength(2));
    });

    test('allows a different category with the same period', () async {
      await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
      );
      await controller.create(
        categoryId: 'test-transport',
        amountMinor: 500000,
        period: BudgetPeriod.monthly,
      );

      expect(await dao.getAll(), hasLength(2));
    });

    test('allows a new budget once the previous one is archived', () async {
      final first = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
      );
      await controller.archive(first);

      final second = await controller.create(
        categoryId: 'test-food',
        amountMinor: 2000000,
        period: BudgetPeriod.monthly,
      );

      expect(second, isNot(first));
      expect(await dao.getAll(), hasLength(2));
    });
  });

  group('update', () {
    test('changes the limit and period', () async {
      final id = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 8, 1),
      );
      final before = await dao.getById(id);

      await controller.update(
        id: id,
        amountMinor: 1500000,
        period: BudgetPeriod.weekly,
        startDate: DateTime(2026, 8, 1),
      );

      final after = await dao.getById(id);
      expect(after!.amountMinor, 1500000);
      expect(after.period, BudgetPeriod.weekly);
      // The category is fixed at creation.
      expect(after.categoryId, before!.categoryId);
      expect(
        after.updatedAt.isAfter(before.updatedAt) ||
            after.updatedAt == before.updatedAt,
        isTrue,
      );
    });

    test('does not collide with itself on the uniqueness check', () async {
      final id = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
      );

      await controller.update(
        id: id,
        amountMinor: 2000000,
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 8, 1),
      );

      expect((await dao.getById(id))!.amountMinor, 2000000);
    });

    test(
      'rejects switching onto a period another budget already covers',
      () async {
        final monthly = await controller.create(
          categoryId: 'test-food',
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
        );
        await controller.create(
          categoryId: 'test-food',
          amountMinor: 250000,
          period: BudgetPeriod.weekly,
        );

        expect(
          () => controller.update(
            id: monthly,
            amountMinor: 1000000,
            period: BudgetPeriod.weekly,
            startDate: DateTime(2026, 8, 1),
          ),
          throwsArgumentError,
        );
      },
    );

    test('rejects a zero limit', () async {
      final id = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
      );

      expect(
        () => controller.update(
          id: id,
          amountMinor: 0,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 8, 1),
        ),
        throwsArgumentError,
      );
    });

    test('throws for an unknown budget', () async {
      expect(
        () => controller.update(
          id: 'nope',
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 8, 1),
        ),
        throwsStateError,
      );
    });
  });

  group('lifecycle', () {
    test('archive then restore returns a budget to active', () async {
      final id = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
      );

      await controller.archive(id);
      expect((await dao.getById(id))!.status, BudgetStatus.archived);

      await controller.restore(id);
      expect((await dao.getById(id))!.status, BudgetStatus.active);
    });

    test('restore is blocked when an active budget took its place', () async {
      final first = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
      );
      await controller.archive(first);
      await controller.create(
        categoryId: 'test-food',
        amountMinor: 2000000,
        period: BudgetPeriod.monthly,
      );

      expect(() => controller.restore(first), throwsArgumentError);
      expect((await dao.getById(first))!.status, BudgetStatus.archived);
    });

    test('restore throws for an unknown budget', () async {
      expect(() => controller.restore('nope'), throwsStateError);
    });

    test('archive throws for an unknown budget', () async {
      expect(() => controller.archive('nope'), throwsStateError);
    });

    test('delete removes the budget', () async {
      final id = await controller.create(
        categoryId: 'test-food',
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
      );

      await controller.delete(id);

      expect(await dao.getById(id), isNull);
    });
  });
}
