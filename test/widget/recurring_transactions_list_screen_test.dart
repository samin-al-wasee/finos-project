import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';

import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/recurring/data/recurring_transaction_dao.dart';
import 'package:finos_app/features/recurring/domain/recurrence_frequency.dart';
import 'package:finos_app/features/recurring/presentation/recurring_transaction_form_screen.dart';
import 'package:finos_app/features/recurring/presentation/recurring_transactions_list_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the recurring transactions screen (docs/ROADMAP.md §8.1).
///
/// Each test closes the database before returning: the underlying streams
/// carry an open-timeout timer, and the test framework asserts no timers are
/// pending once the widget tree is disposed.
void main() {
  Future<AppDatabase> seedDatabase() async {
    final database = AppDatabase.inMemory();
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    return database;
  }

  Future<void> pumpScreen(WidgetTester tester, AppDatabase database) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const RecurringTransactionsListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty state when there are no rules', (tester) async {
    final database = await seedDatabase();
    await pumpScreen(tester, database);

    expect(find.text('No recurring transactions yet'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Add recurring transaction'),
      findsOneWidget,
    );

    await database.close();
  });

  testWidgets('the FAB opens the recurring transaction form', (tester) async {
    final database = await seedDatabase();
    await pumpScreen(tester, database);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(RecurringTransactionFormScreen), findsOneWidget);
    expect(
      find.widgetWithText(AppBar, 'New recurring transaction'),
      findsOneWidget,
    );

    await database.close();
  });

  testWidgets('an active rule with nothing due shows only in Active', (
    tester,
  ) async {
    final database = await seedDatabase();
    final farFuture = DateTime.now().add(const Duration(days: 365));
    await RecurringTransactionDao(database).insertOne(
      RecurringTransactionsCompanion.insert(
        id: 'rec-1',
        name: 'Netflix',
        type: TransactionType.expense,
        amountMinor: 50000,
        accountId: 'acct-bank',
        frequency: RecurrenceFrequency.monthly,
        startDate: farFuture,
        nextOccurrence: farFuture,
      ),
    );
    await pumpScreen(tester, database);

    expect(find.text('Due'), findsNothing);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);

    await database.close();
  });

  group('a rule with a due occurrence', () {
    /// Seeds a daily rule whose next occurrence is [daysOverdue] days before
    /// today, so exactly `daysOverdue + 1` occurrences are due as of now (today
    /// itself always counts).
    Future<AppDatabase> seedDueRule({int daysOverdue = 0}) async {
      final database = await seedDatabase();
      final today = DateTime.now();
      final due = DateTime(today.year, today.month, today.day - daysOverdue);
      await RecurringTransactionDao(database).insertOne(
        RecurringTransactionsCompanion.insert(
          id: 'rec-1',
          name: 'Netflix',
          type: TransactionType.expense,
          amountMinor: 50000,
          accountId: 'acct-bank',
          frequency: RecurrenceFrequency.daily,
          startDate: due,
          nextOccurrence: due,
        ),
      );
      return database;
    }

    testWidgets('shows in the Due section with a Confirm action', (
      tester,
    ) async {
      final database = await seedDueRule();
      await pumpScreen(tester, database);

      expect(find.text('Due'), findsOneWidget);
      expect(find.text('Netflix'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Skip'), findsOneWidget);

      await database.close();
    });

    testWidgets('confirming creates a transaction and clears the due card', (
      tester,
    ) async {
      final database = await seedDueRule();
      await pumpScreen(tester, database);

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Due'), findsNothing);
      final transactions = await TransactionDao(database).getAll();
      expect(transactions, hasLength(1));
      expect(transactions.single.amountMinor, 50000);
      expect(transactions.single.accountId, 'acct-bank');

      await database.close();
    });

    testWidgets('skipping clears the due card without creating a transaction', (
      tester,
    ) async {
      final database = await seedDueRule();
      await pumpScreen(tester, database);

      await tester.tap(find.widgetWithText(TextButton, 'Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Due'), findsNothing);
      expect(await TransactionDao(database).getAll(), isEmpty);

      await database.close();
    });

    testWidgets(
      'a backlog of more than one offers Confirm next/all and Skip all',
      (tester) async {
        final database = await seedDueRule(daysOverdue: 3);
        await pumpScreen(tester, database);

        expect(
          find.widgetWithText(OutlinedButton, 'Confirm next'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Confirm all'),
          findsOneWidget,
        );
        expect(find.widgetWithText(TextButton, 'Skip all'), findsOneWidget);

        await database.close();
      },
    );

    testWidgets('confirm next only creates one transaction from the backlog', (
      tester,
    ) async {
      final database = await seedDueRule(daysOverdue: 3);
      await pumpScreen(tester, database);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Confirm next'));
      await tester.pumpAndSettle();

      expect(await TransactionDao(database).getAll(), hasLength(1));
      // Still due — three days overdue, only one confirmed.
      expect(find.text('Due'), findsOneWidget);

      await database.close();
    });

    testWidgets('confirm all creates a transaction for every due occurrence', (
      tester,
    ) async {
      final database = await seedDueRule(daysOverdue: 3);
      await pumpScreen(tester, database);

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm all'));
      await tester.pumpAndSettle();

      final transactions = await TransactionDao(database).getAll();
      expect(transactions, hasLength(4));
      expect(find.text('Due'), findsNothing);

      await database.close();
    });
  });

  group('managing a rule', () {
    Future<AppDatabase> seedRule(AppDatabase database) async {
      await RecurringTransactionDao(database).insertOne(
        RecurringTransactionsCompanion.insert(
          id: 'rec-1',
          name: 'Netflix',
          type: TransactionType.expense,
          amountMinor: 50000,
          accountId: 'acct-bank',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime.now().add(const Duration(days: 365)),
          nextOccurrence: DateTime.now().add(const Duration(days: 365)),
        ),
      );
      return database;
    }

    testWidgets('tapping a rule opens its edit form', (tester) async {
      final database = await seedRule(await seedDatabase());
      await pumpScreen(tester, database);

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();

      expect(find.byType(RecurringTransactionFormScreen), findsOneWidget);
      expect(
        find.widgetWithText(AppBar, 'Edit recurring transaction'),
        findsOneWidget,
      );

      await database.close();
    });

    testWidgets('the menu archives and restores a rule', (tester) async {
      final database = await seedRule(await seedDatabase());
      await pumpScreen(tester, database);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsNothing);
      expect(find.text('Archived'), findsOneWidget);
      expect(
        (await RecurringTransactionDao(database).getById('rec-1'))!.status.name,
        'archived',
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Archived'), findsNothing);

      await database.close();
    });

    testWidgets('delete requires confirmation and removes the rule', (
      tester,
    ) async {
      final database = await seedRule(await seedDatabase());
      await pumpScreen(tester, database);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this recurring transaction?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        await RecurringTransactionDao(database).getById('rec-1'),
        isNotNull,
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await RecurringTransactionDao(database).getById('rec-1'), isNull);
      expect(find.text('No recurring transactions yet'), findsOneWidget);

      await database.close();
    });
  });
}
