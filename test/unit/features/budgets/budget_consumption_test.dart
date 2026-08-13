import 'package:drift/drift.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_rollover.dart';
import 'package:finos_app/features/budgets/domain/budget_scope.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [TransactionDao.expenseTotalForCategory] — the budget-consumption
/// rule (docs/DATA_MODEL.md §24).
///
/// Only expenses in the budget's own category, inside the half-open window,
/// count towards a budget. Income is not spending, and a transfer moves the
/// user's own money between accounts, so neither may consume a budget
/// (docs/DATA_MODEL.md §17).
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late CategoryDao categories;
  late TransactionDao dao;

  final from = DateTime(2026, 8, 1);
  final to = DateTime(2026, 9, 1);

  setUp(() async {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    categories = CategoryDao(database);
    dao = TransactionDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-main',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-cash',
        name: 'Cash',
        type: AccountType.cash,
      ),
    );
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
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> add(
    String id, {
    required DateTime date,
    TransactionType type = TransactionType.expense,
    int amountMinor = 100000,
    String? categoryId = 'test-food',
    String accountId = 'acct-main',
    String? destinationAccountId,
  }) async {
    await dao.insertOne(
      TransactionsCompanion.insert(
        id: id,
        type: type,
        amountMinor: amountMinor,
        accountId: accountId,
        destinationAccountId: Value(destinationAccountId),
        categoryId: Value(categoryId),
        date: date,
      ),
    );
  }

  group('expenseTotalForCategory', () {
    test('is zero when the category has no transactions', () async {
      expect(await dao.expenseTotalForCategory('test-food', from, to), 0);
    });

    test('sums expenses in the category', () async {
      // The worked example from docs/DATA_MODEL.md §24: 2,000 + 1,500 + 1,200.
      await add('tx-1', date: DateTime(2026, 8, 3), amountMinor: 200000);
      await add('tx-2', date: DateTime(2026, 8, 12), amountMinor: 150000);
      await add('tx-3', date: DateTime(2026, 8, 25), amountMinor: 120000);

      expect(await dao.expenseTotalForCategory('test-food', from, to), 470000);
    });

    test('ignores expenses in other categories', () async {
      await add('tx-food', date: DateTime(2026, 8, 5), amountMinor: 100000);
      await add(
        'tx-transport',
        date: DateTime(2026, 8, 6),
        amountMinor: 300000,
        categoryId: 'test-transport',
      );

      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);
    });

    test('ignores uncategorised expenses', () async {
      await add('tx-food', date: DateTime(2026, 8, 5), amountMinor: 100000);
      await add(
        'tx-none',
        date: DateTime(2026, 8, 6),
        amountMinor: 500000,
        categoryId: null,
      );

      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);
    });

    test('excludes income even in a matching category', () async {
      await add(
        'tx-income',
        date: DateTime(2026, 8, 5),
        type: TransactionType.income,
        amountMinor: 900000,
        categoryId: 'test-salary',
      );

      expect(await dao.expenseTotalForCategory('test-salary', from, to), 0);
    });

    test('excludes transfers', () async {
      // Transfers always carry a null category, and the query filters on type
      // as well — belt and braces, because a transfer must never consume a
      // budget (docs/DATA_MODEL.md §17).
      await add(
        'tx-transfer',
        date: DateTime(2026, 8, 5),
        type: TransactionType.transfer,
        amountMinor: 500000,
        categoryId: null,
        destinationAccountId: 'acct-cash',
      );
      await add('tx-food', date: DateTime(2026, 8, 6), amountMinor: 100000);

      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);
    });

    test('counts spending from every account', () async {
      await add('tx-bank', date: DateTime(2026, 8, 5), amountMinor: 100000);
      await add(
        'tx-cash',
        date: DateTime(2026, 8, 6),
        amountMinor: 250000,
        accountId: 'acct-cash',
      );

      expect(await dao.expenseTotalForCategory('test-food', from, to), 350000);
    });
  });

  group('window boundaries', () {
    test('includes the first moment of the window', () async {
      await add('tx-first', date: DateTime(2026, 8, 1), amountMinor: 100000);

      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);
    });

    test('includes the last day of the window', () async {
      await add(
        'tx-last',
        date: DateTime(2026, 8, 31, 23, 59, 59),
        amountMinor: 100000,
      );

      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);
    });

    test('excludes the upper bound itself', () async {
      // Half-open range: a September 1st expense belongs to September's budget.
      await add('tx-next', date: DateTime(2026, 9, 1), amountMinor: 100000);

      expect(await dao.expenseTotalForCategory('test-food', from, to), 0);
    });

    test('excludes spending before the window', () async {
      await add('tx-prev', date: DateTime(2026, 7, 31), amountMinor: 100000);

      expect(await dao.expenseTotalForCategory('test-food', from, to), 0);
    });

    test('a deleted expense stops counting towards the budget', () async {
      await add('tx-food', date: DateTime(2026, 8, 5), amountMinor: 100000);
      expect(await dao.expenseTotalForCategory('test-food', from, to), 100000);

      await dao.deleteOne('tx-food');
      expect(await dao.expenseTotalForCategory('test-food', from, to), 0);
    });
  });

  // The multi-category, uncategorized, and whole-account generalisations of
  // expenseTotalForCategory (docs/adr/007-flexible-budget-scope.md). Same
  // window/type rules; only the category filter changes shape.
  group('expenseTotalForCategories', () {
    test('is zero when none of the categories have transactions', () async {
      expect(
        await dao.expenseTotalForCategories(
          ['test-food', 'test-transport'],
          from,
          to,
        ),
        0,
      );
    });

    test('is zero for an empty category set', () async {
      expect(await dao.expenseTotalForCategories([], from, to), 0);
    });

    test('sums expenses across every listed category — one IN query', () async {
      await add('tx-food', date: DateTime(2026, 8, 3), amountMinor: 200000);
      await add(
        'tx-transport',
        date: DateTime(2026, 8, 12),
        amountMinor: 150000,
        categoryId: 'test-transport',
      );

      expect(
        await dao.expenseTotalForCategories(
          ['test-food', 'test-transport'],
          from,
          to,
        ),
        350000,
      );
    });

    test('ignores categories outside the listed set', () async {
      await add('tx-food', date: DateTime(2026, 8, 3), amountMinor: 200000);
      await add(
        'tx-transport',
        date: DateTime(2026, 8, 12),
        amountMinor: 150000,
        categoryId: 'test-transport',
      );

      expect(
        await dao.expenseTotalForCategories(['test-food'], from, to),
        200000,
      );
    });

    test('excludes income and transfers', () async {
      await add(
        'tx-income',
        date: DateTime(2026, 8, 5),
        type: TransactionType.income,
        amountMinor: 900000,
        categoryId: 'test-salary',
      );
      await add('tx-food', date: DateTime(2026, 8, 6), amountMinor: 100000);

      expect(
        await dao.expenseTotalForCategories(
          ['test-food', 'test-salary'],
          from,
          to,
        ),
        100000,
      );
    });

    test('respects the half-open window', () async {
      await add('tx-next', date: DateTime(2026, 9, 1), amountMinor: 100000);

      expect(await dao.expenseTotalForCategories(['test-food'], from, to), 0);
    });

    test('a deleted expense stops counting', () async {
      await add('tx-food', date: DateTime(2026, 8, 5), amountMinor: 100000);
      expect(
        await dao.expenseTotalForCategories(['test-food'], from, to),
        100000,
      );

      await dao.deleteOne('tx-food');
      expect(await dao.expenseTotalForCategories(['test-food'], from, to), 0);
    });
  });

  group('expenseTotalUncategorized', () {
    test('is zero when there are no uncategorised expenses', () async {
      expect(await dao.expenseTotalUncategorized(from, to), 0);
    });

    test('sums only expenses with no category', () async {
      await add('tx-food', date: DateTime(2026, 8, 5), amountMinor: 100000);
      await add(
        'tx-none-1',
        date: DateTime(2026, 8, 6),
        amountMinor: 300000,
        categoryId: null,
      );
      await add(
        'tx-none-2',
        date: DateTime(2026, 8, 7),
        amountMinor: 200000,
        categoryId: null,
      );

      expect(await dao.expenseTotalUncategorized(from, to), 500000);
    });

    test('excludes uncategorised income and transfers', () async {
      await add(
        'tx-income',
        date: DateTime(2026, 8, 5),
        type: TransactionType.income,
        amountMinor: 900000,
        categoryId: null,
      );
      await add(
        'tx-transfer',
        date: DateTime(2026, 8, 6),
        type: TransactionType.transfer,
        amountMinor: 500000,
        categoryId: null,
        destinationAccountId: 'acct-cash',
      );

      expect(await dao.expenseTotalUncategorized(from, to), 0);
    });

    test('respects the half-open window', () async {
      await add(
        'tx-next',
        date: DateTime(2026, 9, 1),
        amountMinor: 100000,
        categoryId: null,
      );

      expect(await dao.expenseTotalUncategorized(from, to), 0);
    });

    test('a deleted expense stops counting', () async {
      await add(
        'tx-none',
        date: DateTime(2026, 8, 5),
        amountMinor: 100000,
        categoryId: null,
      );
      expect(await dao.expenseTotalUncategorized(from, to), 100000);

      await dao.deleteOne('tx-none');
      expect(await dao.expenseTotalUncategorized(from, to), 0);
    });
  });

  group('expenseTotalAll', () {
    test('is zero when there are no expenses', () async {
      expect(await dao.expenseTotalAll(from, to), 0);
    });

    test('sums every expense regardless of category', () async {
      await add('tx-food', date: DateTime(2026, 8, 3), amountMinor: 200000);
      await add(
        'tx-transport',
        date: DateTime(2026, 8, 12),
        amountMinor: 150000,
        categoryId: 'test-transport',
      );
      await add(
        'tx-none',
        date: DateTime(2026, 8, 13),
        amountMinor: 100000,
        categoryId: null,
      );

      expect(await dao.expenseTotalAll(from, to), 450000);
    });

    test('excludes income and transfers', () async {
      await add(
        'tx-income',
        date: DateTime(2026, 8, 5),
        type: TransactionType.income,
        amountMinor: 900000,
        categoryId: 'test-salary',
      );
      await add(
        'tx-transfer',
        date: DateTime(2026, 8, 6),
        type: TransactionType.transfer,
        amountMinor: 500000,
        categoryId: null,
        destinationAccountId: 'acct-cash',
      );
      await add('tx-food', date: DateTime(2026, 8, 7), amountMinor: 100000);

      expect(await dao.expenseTotalAll(from, to), 100000);
    });

    test('respects the half-open window', () async {
      await add('tx-next', date: DateTime(2026, 9, 1), amountMinor: 100000);

      expect(await dao.expenseTotalAll(from, to), 0);
    });

    test('a deleted expense stops counting', () async {
      await add('tx-food', date: DateTime(2026, 8, 5), amountMinor: 100000);
      expect(await dao.expenseTotalAll(from, to), 100000);

      await dao.deleteOne('tx-food');
      expect(await dao.expenseTotalAll(from, to), 0);
    });
  });

  group('rollover end-to-end (docs/adr/008-budget-rollover.md)', () {
    late BudgetDao budgets;

    setUp(() {
      budgets = BudgetDao(database);
    });

    /// Mirrors `lib/app/providers.dart`'s private `_spentMinorForScope`
    /// dispatcher, built from the real, public [TransactionDao] queries —
    /// exercising the same generalisation against a real in-memory database
    /// rather than a fake, window-only `SpendLookup`.
    Future<int> spentForScope(BudgetScope scope, DateTime from, DateTime to) {
      return switch (scope) {
        SingleCategoryScope(:final categoryId) => dao.expenseTotalForCategory(
          categoryId,
          from,
          to,
        ),
        MultiCategoryScope(:final categoryIds) => dao.expenseTotalForCategories(
          categoryIds,
          from,
          to,
        ),
        UncategorizedScope() => dao.expenseTotalUncategorized(from, to),
        WholeAccountScope() => dao.expenseTotalAll(from, to),
      };
    }

    test(
      'a SINGLE_CATEGORY rollover budget carries 3 real monthly windows '
      'into the current effective limit',
      () async {
        // start_date pinned to June so only June and July are eligible ahead
        // of the August "current" period under test.
        await budgets.insertOne(
          BudgetsCompanion.insert(
            id: 'budget-rollover',
            categoryId: const Value('test-food'),
            amountMinor: 1000000, // ৳10,000
            period: BudgetPeriod.monthly,
            startDate: DateTime(2026, 6, 1),
            rolloverEnabled: const Value(true),
          ),
        );
        // June: 6,000 spent of a 10,000 limit → 4,000 unspent.
        await add('tx-jun', date: DateTime(2026, 6, 10), amountMinor: 600000);
        // July: effective limit 10,000 + 4,000 = 14,000; 9,000 spent →
        // 5,000 unspent carries into August.
        await add('tx-jul', date: DateTime(2026, 7, 10), amountMinor: 900000);
        // August (current): 3,000 spent.
        await add('tx-aug', date: DateTime(2026, 8, 10), amountMinor: 300000);

        final budget = (await budgets.getById('budget-rollover'))!;
        const scope = SingleCategoryScope('test-food');
        final reference = DateTime(2026, 8, 15);

        final carriedInMinor = await rolloverCarryInMinor(
          budget: budget,
          reference: reference,
          spentBetween: (from, to) => spentForScope(scope, from, to),
        );
        expect(carriedInMinor, 500000); // ৳5,000

        final window = budgetWindow(
          BudgetPeriod.monthly,
          reference: reference,
          startDate: budget.startDate,
        );
        final spentMinor = await spentForScope(scope, window.from, window.to);
        final effectiveLimitMinor = budget.amountMinor + carriedInMinor;

        expect(spentMinor, 300000);
        expect(effectiveLimitMinor, 1500000); // ৳15,000
        expect(effectiveLimitMinor - spentMinor, 1200000); // ৳12,000
      },
    );

    test(
      'an archive/restore gap in between periods does not change the '
      'carry-in calendar walk',
      () async {
        await budgets.insertOne(
          BudgetsCompanion.insert(
            id: 'budget-gap',
            categoryId: const Value('test-food'),
            amountMinor: 1000000,
            period: BudgetPeriod.monthly,
            startDate: DateTime(2026, 6, 1),
            rolloverEnabled: const Value(true),
          ),
        );
        await add('tx-jun', date: DateTime(2026, 6, 10), amountMinor: 700000);
        await add('tx-jul', date: DateTime(2026, 7, 10), amountMinor: 400000);

        const scope = SingleCategoryScope('test-food');
        final reference = DateTime(2026, 8, 15);
        Future<int> computeCarry() async {
          final budget = (await budgets.getById('budget-gap'))!;
          return rolloverCarryInMinor(
            budget: budget,
            reference: reference,
            spentBetween: (from, to) => spentForScope(scope, from, to),
          );
        }

        final before = await computeCarry();

        // Archiving and restoring in between touches only `status`, which the
        // calendar walk never inspects — the same rule
        // `budgetHistoryProvider` already relies on.
        await budgets.updateStatus('budget-gap', BudgetStatus.archived);
        await budgets.updateStatus('budget-gap', BudgetStatus.active);

        final after = await computeCarry();

        expect(after, before);
        // June: 10,000 - 7,000 = 3,000 remainder.
        // July: (10,000 + 3,000) - 4,000 = 9,000 remainder, carried into
        // August.
        expect(after, 900000);
      },
    );

    test(
      'a WHOLE_ACCOUNT rollover budget generalises with no special-casing',
      () async {
        // Proves the window-only SpendLookup generalisation end-to-end for a
        // non-SINGLE_CATEGORY scope, not just SINGLE_CATEGORY.
        await budgets.insertOne(
          BudgetsCompanion.insert(
            id: 'budget-whole',
            categoryId: const Value(null),
            scopeType: const Value(BudgetScopeType.wholeAccount),
            amountMinor: 2000000, // ৳20,000
            period: BudgetPeriod.monthly,
            startDate: DateTime(2026, 7, 1),
            rolloverEnabled: const Value(true),
          ),
        );
        // July: 12,000 food + 3,000 transport = 15,000 spent of a 20,000
        // limit → 5,000 unspent carries into August.
        await add('tx-jul-food', date: DateTime(2026, 7, 5), amountMinor: 1200000);
        await add(
          'tx-jul-transport',
          date: DateTime(2026, 7, 6),
          amountMinor: 300000,
          categoryId: 'test-transport',
        );

        final budget = (await budgets.getById('budget-whole'))!;
        const scope = WholeAccountScope();
        final reference = DateTime(2026, 8, 15);

        final carriedInMinor = await rolloverCarryInMinor(
          budget: budget,
          reference: reference,
          spentBetween: (from, to) => spentForScope(scope, from, to),
        );

        expect(carriedInMinor, 500000); // ৳5,000
      },
    );
  });
}
