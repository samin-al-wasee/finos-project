import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/categories/data/built_in_categories.dart';
import 'package:finos_app/features/categories/domain/category_origin.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/categories/presentation/category_icon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Built-in categories', () {
    test('seed integrity', () {
      final ids = <String>{};

      for (final row in builtInCategories) {
        // Each ID must be unique across the seed set.
        expect(
          ids.add(row.id.value),
          isTrue,
          reason: 'Duplicate ID: ${row.id.value}',
        );

        // Must have a non-empty name.
        expect(
          row.name.value,
          isNotEmpty,
          reason: 'Empty name for ${row.id.value}',
        );

        // Must have a valid type, origin and status.
        expect(
          CategoryType.values.contains(row.type.value),
          isTrue,
          reason: 'Invalid type for ${row.id.value}',
        );
        expect(
          CategoryOrigin.values.contains(row.origin.value),
          isTrue,
          reason: 'Invalid origin for ${row.id.value}',
        );
        expect(
          CategoryStatus.values.contains(row.status.value),
          isTrue,
          reason: 'Invalid status for ${row.id.value}',
        );

        // Every icon key must resolve to an IconData via the presentation helper.
        expect(
          categoryIconKeys.contains(row.icon.value),
          isTrue,
          reason: 'Unknown icon key "${row.icon.value}" for ${row.id.value}',
        );
      }
    });

    test('fresh in-memory database seeds built-in categories', () async {
      final database = AppDatabase.inMemory();
      try {
        final categories = await (database.select(database.categories)).get();
        expect(categories.length, builtInCategories.length);

        final seededIds = categories.map((r) => r.id).toSet();
        for (final seed in builtInCategories) {
          expect(
            seededIds.contains(seed.id.value),
            isTrue,
            reason: 'Missing ${seed.id.value}',
          );
        }
      } finally {
        await database.close();
      }
    });
  });
}
