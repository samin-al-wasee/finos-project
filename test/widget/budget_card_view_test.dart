import 'package:drift/drift.dart' hide isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/budgets/application/budget_controller.dart';
import 'package:finos_app/features/budgets/data/budget_dao.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_scope.dart';
import 'package:finos_app/features/budgets/presentation/budget_details_screen.dart';
import 'package:finos_app/features/budgets/presentation/budgets_list_screen.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the Budgets tab's card view: a swipeable single-budget
/// card with a live spending feed below it, toggled alongside (not
/// replacing) the existing list view.
void main() {
  Future<AppDatabase> seedDatabase() async {
    final database = AppDatabase.inMemory();
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-main',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await CategoryDao(database).insertOne(
      CategoriesCompanion.insert(
        id: 'test-food',
        name: 'Food',
        type: CategoryType.expense,
      ),
    );
    await CategoryDao(database).insertOne(
      CategoriesCompanion.insert(
        id: 'test-transport',
        name: 'Transport',
        type: CategoryType.expense,
      ),
    );
    return database;
  }

  BudgetController controllerFor(AppDatabase database) =>
      BudgetController(BudgetDao(database), CategoryDao(database));

  Future<void> pumpBudgets(WidgetTester tester, AppDatabase database) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const BudgetsListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addExpense(
    AppDatabase database,
    String id,
    int amountMinor, {
    String? categoryId,
    DateTime? date,
  }) async {
    await TransactionDao(database).insertOne(
      TransactionsCompanion.insert(
        id: id,
        type: TransactionType.expense,
        amountMinor: amountMinor,
        accountId: 'acct-main',
        categoryId: Value(categoryId),
        date: date ?? DateTime.now(),
      ),
    );
  }

  testWidgets('the view toggle is hidden when there are no active budgets', (
    tester,
  ) async {
    final database = await seedDatabase();
    await pumpBudgets(tester, database);

    expect(find.byIcon(Icons.view_carousel), findsNothing);

    await database.close();
  });

  testWidgets('the toggle switches between list view and card view, and back', (
    tester,
  ) async {
    final database = await seedDatabase();
    await controllerFor(database).create(
      scope: const SingleCategoryScope('test-food'),
      amountMinor: 500000,
      period: BudgetPeriod.monthly,
    );
    await pumpBudgets(tester, database);

    expect(find.byType(PageView), findsNothing);

    await tester.tap(find.byIcon(Icons.view_carousel));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);

    await tester.tap(find.byIcon(Icons.view_list));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);

    await database.close();
  });

  testWidgets(
    "a single-category budget's feed shows only its own category's spend",
    (tester) async {
      final database = await seedDatabase();
      await controllerFor(database).create(
        scope: const SingleCategoryScope('test-food'),
        amountMinor: 500000,
        period: BudgetPeriod.monthly,
      );
      await addExpense(database, 'tx-food', 5000, categoryId: 'test-food');
      await addExpense(
        database,
        'tx-transport',
        3000,
        categoryId: 'test-transport',
      );
      await pumpBudgets(tester, database);

      await tester.tap(find.byIcon(Icons.view_carousel));
      await tester.pumpAndSettle();

      expect(find.text('Food'), findsWidgets);
      expect(
        find.text('No spending recorded for this period yet'),
        findsNothing,
      );
      // The category-name tile text ("Food"/"Transport") is what
      // TransactionTile shows as its title, so a Transport-only transaction
      // should not be findable inside a Food budget's feed.
      expect(find.text('Transport'), findsNothing);

      await database.close();
    },
  );

  testWidgets(
    'a whole-account budget includes every category but excludes income',
    (tester) async {
      final database = await seedDatabase();
      await controllerFor(database).create(
        scope: const WholeAccountScope(),
        amountMinor: 500000,
        period: BudgetPeriod.monthly,
      );
      await addExpense(database, 'tx-food', 5000, categoryId: 'test-food');
      await addExpense(
        database,
        'tx-transport',
        3000,
        categoryId: 'test-transport',
      );
      await TransactionDao(database).insertOne(
        TransactionsCompanion.insert(
          id: 'tx-income',
          type: TransactionType.income,
          amountMinor: 100000,
          accountId: 'acct-main',
          date: DateTime.now(),
        ),
      );
      await pumpBudgets(tester, database);

      await tester.tap(find.byIcon(Icons.view_carousel));
      await tester.pumpAndSettle();

      expect(find.text('Food'), findsWidgets);
      expect(find.text('Transport'), findsWidgets);
      expect(find.text('+৳1,000.00'), findsNothing);

      await database.close();
    },
  );

  testWidgets(
    'an uncategorized-scope budget shows only categoryless expenses',
    (tester) async {
      final database = await seedDatabase();
      await controllerFor(database).create(
        scope: const UncategorizedScope(),
        amountMinor: 500000,
        period: BudgetPeriod.monthly,
      );
      await addExpense(database, 'tx-none', 2000);
      await addExpense(database, 'tx-food', 5000, categoryId: 'test-food');
      await pumpBudgets(tester, database);

      await tester.tap(find.byIcon(Icons.view_carousel));
      await tester.pumpAndSettle();

      expect(find.text('Transaction'), findsOneWidget);
      expect(find.text('Food'), findsNothing);

      await database.close();
    },
  );

  testWidgets('a transaction outside the current window is excluded', (
    tester,
  ) async {
    final database = await seedDatabase();
    await controllerFor(database).create(
      scope: const SingleCategoryScope('test-food'),
      amountMinor: 500000,
      period: BudgetPeriod.monthly,
    );
    final lastMonth = DateTime.now().subtract(const Duration(days: 45));
    await addExpense(
      database,
      'tx-old',
      5000,
      categoryId: 'test-food',
      date: lastMonth,
    );
    await pumpBudgets(tester, database);

    await tester.tap(find.byIcon(Icons.view_carousel));
    await tester.pumpAndSettle();

    expect(
      find.text('No spending recorded for this period yet'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await database.close();
  });

  testWidgets('tapping a card opens the existing Budget Details screen', (
    tester,
  ) async {
    final database = await seedDatabase();
    await controllerFor(database).create(
      scope: const SingleCategoryScope('test-food'),
      amountMinor: 500000,
      period: BudgetPeriod.monthly,
    );
    await pumpBudgets(tester, database);

    await tester.tap(find.byIcon(Icons.view_carousel));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Food').first);
    await tester.pumpAndSettle();

    expect(find.byType(BudgetDetailsScreen), findsOneWidget);

    await database.close();
  });
}
