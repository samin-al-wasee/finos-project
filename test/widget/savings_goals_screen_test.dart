import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/savings_goals/application/savings_goal_controller.dart';
import 'package:finos_app/features/savings_goals/data/savings_goal_dao.dart';
import 'package:finos_app/features/savings_goals/presentation/savings_goal_details_screen.dart';
import 'package:finos_app/features/savings_goals/presentation/savings_goal_form_screen.dart';
import 'package:finos_app/features/savings_goals/presentation/savings_goals_list_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the Savings Goals screen and its detail screen
/// (docs/adr/011-savings-goals.md).
void main() {
  /// Creates a database with one active account to move goal money through.
  Future<AppDatabase> seedDatabase() async {
    final database = AppDatabase.inMemory();
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(10000000),
      ),
    );
    return database;
  }

  SavingsGoalController controllerFor(AppDatabase database) =>
      SavingsGoalController(
        database,
        SavingsGoalDao(database),
        TransactionDao(database),
        AccountDao(database),
      );

  Future<void> pumpGoals(WidgetTester tester, AppDatabase database) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SavingsGoalsListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('list', () {
    testWidgets('shows an empty state with no goals', (tester) async {
      final database = await seedDatabase();
      await pumpGoals(tester, database);

      expect(find.text('No savings goals yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add goal'), findsOneWidget);

      await database.close();
    });

    testWidgets('the empty state opens the goal form', (tester) async {
      final database = await seedDatabase();
      await pumpGoals(tester, database);

      await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
      await tester.pumpAndSettle();

      expect(find.byType(SavingsGoalFormScreen), findsOneWidget);

      await database.close();
    });

    testWidgets('lists a created goal with its saved amount', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final id = await controller.create(
        name: 'Emergency Fund',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
      );
      await controller.contribute(goalId: id, amountMinor: 250000);
      await pumpGoals(tester, database);

      expect(find.text('Emergency Fund'), findsOneWidget);
      expect(find.textContaining('৳2,500'), findsWidgets);

      await database.close();
    });
  });

  group('create', () {
    testWidgets('creates a goal', (tester) async {
      final database = await seedDatabase();
      await pumpGoals(tester, database);

      await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Goal name'),
        'New Laptop',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Target amount'),
        '150000',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Bank').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
      await tester.pumpAndSettle();

      expect(find.byType(SavingsGoalFormScreen), findsNothing);
      expect(find.text('New Laptop'), findsOneWidget);

      await database.close();
    });

    testWidgets('requires a name', (tester) async {
      final database = await seedDatabase();
      await pumpGoals(tester, database);

      await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Target amount'),
        '150000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a name for this goal'), findsOneWidget);

      await database.close();
    });

    testWidgets('requires a positive target amount', (tester) async {
      final database = await seedDatabase();
      await pumpGoals(tester, database);

      await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Goal name'),
        'New Laptop',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a target amount'), findsOneWidget);

      await database.close();
    });
  });

  group('details', () {
    Future<void> pumpDetails(
      WidgetTester tester,
      AppDatabase database,
      String goalId,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: SavingsGoalDetailsScreen(goalId: goalId),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the target and saved figures', (tester) async {
      final database = await seedDatabase();
      final id = await controllerFor(database).create(
        name: 'Emergency Fund',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
      );
      await pumpDetails(tester, database, id);

      expect(find.text('Target'), findsOneWidget);
      expect(find.textContaining('৳10,000'), findsWidgets);
      expect(find.text('Active'), findsOneWidget);

      await database.close();
    });

    testWidgets('contributing updates the saved amount', (tester) async {
      final database = await seedDatabase();
      final id = await controllerFor(database).create(
        name: 'Emergency Fund',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
      );
      await pumpDetails(tester, database, id);

      await tester.tap(find.widgetWithText(FilledButton, 'Contribute'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '2500');
      await tester.tap(find.widgetWithText(FilledButton, 'Contribute').last);
      await tester.pumpAndSettle();

      expect(find.text('Contribution recorded'), findsOneWidget);
      final progress = await controllerFor(
        database,
      ).progressFor((await SavingsGoalDao(database).getById(id))!);
      expect(progress.currentAmountMinor, 250000);

      await database.close();
    });

    testWidgets(
      'reaching the target shows Achieved without stopping contributions',
      (tester) async {
        final database = await seedDatabase();
        final controller = controllerFor(database);
        final id = await controller.create(
          name: 'Emergency Fund',
          targetAmountMinor: 1000000,
          accountId: 'acct-bank',
        );
        await controller.contribute(goalId: id, amountMinor: 1000000);
        await pumpDetails(tester, database, id);

        expect(find.text('Achieved'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Contribute'), findsOneWidget);

        await database.close();
      },
    );

    testWidgets('withdrawing reduces the saved amount', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final id = await controller.create(
        name: 'Emergency Fund',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
      );
      await controller.contribute(goalId: id, amountMinor: 500000);
      await pumpDetails(tester, database, id);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Withdraw'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '2000');
      await tester.tap(find.widgetWithText(FilledButton, 'Withdraw'));
      await tester.pumpAndSettle();

      expect(find.text('Withdrawal recorded'), findsOneWidget);
      final progress = await controller.progressFor(
        (await SavingsGoalDao(database).getById(id))!,
      );
      expect(progress.currentAmountMinor, 300000);

      await database.close();
    });

    testWidgets('no Withdraw action with nothing saved yet', (tester) async {
      final database = await seedDatabase();
      final id = await controllerFor(database).create(
        name: 'Emergency Fund',
        targetAmountMinor: 1000000,
        accountId: 'acct-bank',
      );
      await pumpDetails(tester, database, id);

      expect(find.widgetWithText(OutlinedButton, 'Withdraw'), findsNothing);

      await database.close();
    });

    testWidgets(
      'refuses to delete once a contribution is recorded, but archive works',
      (tester) async {
        final database = await seedDatabase();
        final controller = controllerFor(database);
        final id = await controller.create(
          name: 'Emergency Fund',
          targetAmountMinor: 1000000,
          accountId: 'acct-bank',
        );
        await controller.contribute(goalId: id, amountMinor: 100000);
        await pumpDetails(tester, database, id);

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Archive it instead'), findsOneWidget);
        expect(await SavingsGoalDao(database).getById(id), isNotNull);

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();

        expect(find.text('Archived'), findsOneWidget);

        await database.close();
      },
    );
  });
}
