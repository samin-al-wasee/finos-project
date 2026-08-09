import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CategoryDao', () {
    late AppDatabase database;
    late CategoryDao dao;

    setUp(() {
      database = AppDatabase.inMemory();
      dao = CategoryDao(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> seed(
      String name, {
      CategoryType type = CategoryType.expense,
      CategoryStatus status = CategoryStatus.active,
    }) async {
      final id = 'cat-$name';
      await dao.insertOne(
        CategoriesCompanion.insert(
          id: id,
          name: name,
          type: type,
          status: Value(status),
        ),
      );
      return id;
    }

    test('getById returns the matching row', () async {
      await seed('Food');
      await seed('Transport');

      final row = await dao.getById('cat-Transport');
      expect(row, isNotNull);
      expect(row!.name, 'Transport');
    });

    test('getById returns null when no row matches', () async {
      expect(await dao.getById('missing'), isNull);
    });

    test('getAll returns all categories ordered by name', () async {
      await seed('Shopping', type: CategoryType.expense);
      await seed('Food', type: CategoryType.expense);
      await seed('Salary', type: CategoryType.income);
      await seed('Archived', status: CategoryStatus.archived);

      final rows = await dao.getAll();
      final names = rows.map((r) => r.name).toList();

      // Custom categories appear alongside the 12 built-in seeds, ordered by
      // name. Archived rows are included so screens can render a restore
      // section.
      expect(names, containsAll(['Food', 'Shopping', 'Salary', 'Archived']));
      final sorted = [...names]..sort();
      expect(names, orderedEquals(sorted));
    });

    test('updateOne replaces the row contents', () async {
      final id = await seed('Before');

      final row = await dao.getById(id);
      await dao.updateOne(row!.copyWith(name: 'After'));

      final updated = await dao.getById(id);
      expect(updated!.name, 'After');
    });

    test('updateStatus transitions the lifecycle status', () async {
      final id = await seed('Status');

      await dao.updateStatus(id, CategoryStatus.archived);
      expect((await dao.getById(id))!.status, CategoryStatus.archived);

      await dao.updateStatus(id, CategoryStatus.active);
      expect((await dao.getById(id))!.status, CategoryStatus.active);
    });

    test('updateStatus throws StateError for an unknown id', () async {
      expect(
        () => dao.updateStatus('missing', CategoryStatus.archived),
        throwsStateError,
      );
    });
  });
}
