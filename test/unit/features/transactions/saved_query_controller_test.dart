import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/transactions/application/saved_query_controller.dart';
import 'package:finos_app/features/transactions/data/saved_query_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [SavedQueryController] — a saved query is a named, reusable set
/// of structured filter criteria (docs/ROADMAP.md §8.5); it never touches a
/// transaction, an account balance, or a budget.
void main() {
  group('SavedQueryController', () {
    late AppDatabase database;
    late SavedQueryDao dao;
    late SavedQueryController controller;

    setUp(() {
      database = AppDatabase.inMemory();
      dao = SavedQueryDao(database);
      controller = SavedQueryController(dao);
    });

    tearDown(() async {
      await database.close();
    });

    test('save persists the filter under the given name', () async {
      const filter = TransactionFilter(categoryId: 'cat-food');
      final id = await controller.save(name: 'Food', filter: filter);

      final row = await dao.getById(id);
      expect(row, isNotNull);
      expect(row!.name, 'Food');
      expect(controller.filterFor(row).categoryId, 'cat-food');
    });

    test('trims the name', () async {
      const filter = TransactionFilter(categoryId: 'cat-food');
      final id = await controller.save(name: '  Food  ', filter: filter);
      expect((await dao.getById(id))!.name, 'Food');
    });

    test('rejects a blank name', () {
      const filter = TransactionFilter(categoryId: 'cat-food');
      expect(
        () => controller.save(name: '   ', filter: filter),
        throwsArgumentError,
      );
    });

    test('rejects a filter with no criteria set', () {
      expect(
        () => controller.save(
          name: 'Everything',
          filter: const TransactionFilter(),
        ),
        throwsArgumentError,
      );
    });

    test(
      'filterFor decodes the stored criteria back into a TransactionFilter',
      () async {
        final filter = TransactionFilter(
          accountId: 'acct-1',
          categoryId: 'cat-food',
          types: {TransactionTypeFilter.expense},
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 7, 31),
          minAmountMinor: 500,
          maxAmountMinor: 2000,
        );
        final id = await controller.save(name: 'Food in July', filter: filter);
        final row = await dao.getById(id);

        final decoded = controller.filterFor(row!);
        expect(decoded.accountId, 'acct-1');
        expect(decoded.categoryId, 'cat-food');
        expect(decoded.types, {TransactionTypeFilter.expense});
        expect(decoded.from, DateTime(2026, 7, 1));
        expect(decoded.to, DateTime(2026, 7, 31));
        expect(decoded.minAmountMinor, 500);
        expect(decoded.maxAmountMinor, 2000);
      },
    );

    test('delete removes the saved query', () async {
      const filter = TransactionFilter(categoryId: 'cat-food');
      final id = await controller.save(name: 'Food', filter: filter);
      await controller.delete(id);
      expect(await dao.getById(id), isNull);
    });
  });
}
