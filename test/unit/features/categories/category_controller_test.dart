import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/categories/application/category_controller.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_origin.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CategoryController', () {
    late AppDatabase database;
    late CategoryDao dao;
    late CategoryController controller;

    setUp(() {
      database = AppDatabase.inMemory();
      dao = CategoryDao(database);
      controller = CategoryController(dao);
    });

    tearDown(() async {
      await database.close();
    });

    test('create generates a stable id and applies the given values', () async {
      final id = await controller.create(
        name: 'Groceries',
        type: CategoryType.expense,
        icon: 'restaurant',
      );

      final row = await controller.getById(id);
      expect(row, isNotNull);
      expect(row!.id, id);
      expect(row.name, 'Groceries');
      expect(row.type, CategoryType.expense);
      expect(row.origin, CategoryOrigin.user);
      expect(row.icon, 'restaurant');
      expect(row.status, CategoryStatus.active);
    });

    test('create defaults icon to label', () async {
      final id = await controller.create(
        name: 'Test',
        type: CategoryType.income,
      );

      final row = await controller.getById(id);
      expect(row!.icon, 'label');
    });

    test('generates unique ids across creates', () async {
      final id1 = await controller.create(
        name: 'A',
        type: CategoryType.expense,
      );
      final id2 = await controller.create(
        name: 'B',
        type: CategoryType.expense,
      );
      expect(id1, isNot(id2));
    });

    test('getById returns null for an unknown id', () async {
      expect(await controller.getById('missing'), isNull);
    });

    test('update changes name and icon, touches updatedAt', () async {
      final id = await controller.create(
        name: 'Food',
        type: CategoryType.expense,
        icon: 'restaurant',
      );

      await _waitForNextSecond();

      await controller.update(id: id, name: 'Groceries', icon: 'shopping_bag');

      final row = await controller.getById(id);
      expect(row!.name, 'Groceries');
      expect(row.icon, 'shopping_bag');
      expect(row.updatedAt.isAfter(row.createdAt), isTrue);
    });

    test('update throws StateError for an unknown id', () async {
      expect(
        () => controller.update(id: 'missing', name: 'x', icon: 'label'),
        throwsStateError,
      );
    });

    test('update throws StateError for a system category', () async {
      final id = await controller.create(
        name: 'Test',
        type: CategoryType.expense,
      );

      // Manually update to system origin for test
      await dao.updateOne(
        (await dao.getById(id))!.copyWith(origin: CategoryOrigin.system),
      );

      expect(
        () => controller.update(id: id, name: 'x', icon: 'label'),
        throwsStateError,
      );
    });

    test('archive and restore transition the lifecycle status', () async {
      final id = await controller.create(
        name: 'Test',
        type: CategoryType.expense,
      );

      await controller.archive(id);
      expect((await controller.getById(id))!.status, CategoryStatus.archived);

      await controller.restore(id);
      expect((await controller.getById(id))!.status, CategoryStatus.active);
    });

    test('archive throws StateError for an unknown id', () async {
      expect(() => controller.archive('missing'), throwsStateError);
    });
  });
}

/// Waits until just past the next whole-second boundary.
Future<void> _waitForNextSecond() async {
  final now = DateTime.now();
  await Future<void>.delayed(
    Duration(milliseconds: 1000 - now.millisecond + 10),
  );
}
