import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:finos_app/features/transactions/presentation/transaction_form_screen.dart';
import 'package:finos_app/features/transactions/presentation/transactions_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppDatabase> pumpList(WidgetTester tester) async {
    final database = AppDatabase.inMemory();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TransactionsListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  testWidgets('shows an empty state when there are no transactions', (
    tester,
  ) async {
    final database = await pumpList(tester);

    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Add transaction'), findsWidgets);

    await database.close();
  });

  testWidgets('empty-state add button opens the transaction form', (
    tester,
  ) async {
    final database = await pumpList(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionFormScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('renders transactions grouped into date sections', (
    tester,
  ) async {
    final database = await pumpList(tester);
    final accounts = AccountDao(database);
    final categories = CategoryDao(database);
    final transactions = TransactionDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'cat-1',
        name: 'Groceries',
        type: CategoryType.expense,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-1',
        type: TransactionType.expense,
        amountMinor: 50000,
        accountId: 'acct-1',
        categoryId: Value('cat-1'),
        date: DateTime(2026, 8, 10),
        description: Value('Weekly groceries'),
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-2',
        type: TransactionType.income,
        amountMinor: 1000000,
        accountId: 'acct-1',
        date: DateTime(2026, 8, 9),
        description: Value('Salary'),
      ),
    );

    // The streams are watched by the list screen, so re-pump to pick them up.
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('-৳500.00'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('+৳10,000.00'), findsOneWidget);
    expect(find.text('Main Bank'), findsWidgets);
    // Today (Aug 10) and yesterday (Aug 9).
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);

    await database.close();
  });

  testWidgets('renders a transfer as Transfer · A → B', (tester) async {
    final database = await pumpList(tester);
    final accounts = AccountDao(database);
    final transactions = TransactionDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-2',
        name: 'Budget',
        type: AccountType.bank,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-1',
        type: TransactionType.transfer,
        amountMinor: 250000,
        accountId: 'acct-1',
        destinationAccountId: Value('acct-2'),
        date: DateTime(2026, 8, 10),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Transfer · Main Bank → Budget'), findsOneWidget);
    expect(find.text('৳2,500.00'), findsOneWidget);

    await database.close();
  });

  testWidgets('tapping a transaction opens the edit form', (tester) async {
    final database = await pumpList(tester);
    final accounts = AccountDao(database);
    final transactions = TransactionDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-1',
        type: TransactionType.expense,
        amountMinor: 50000,
        accountId: 'acct-1',
        date: DateTime(2026, 8, 10),
        description: Value('Lunch'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionFormScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Edit transaction'), findsOneWidget);

    await database.close();
  });

  testWidgets('delete requires confirmation and removes the transaction', (
    tester,
  ) async {
    final database = await pumpList(tester);
    final accounts = AccountDao(database);
    final transactions = TransactionDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-1',
        type: TransactionType.expense,
        amountMinor: 50000,
        accountId: 'acct-1',
        date: DateTime(2026, 8, 10),
        description: Value('Lunch'),
      ),
    );
    await tester.pumpAndSettle();

    // Open the overflow menu and choose Delete.
    await tester.tap(find.byTooltip('Transaction options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Confirmation dialog appears.
    expect(find.text('Delete this transaction?'), findsOneWidget);

    // Cancel leaves the transaction in place.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await transactions.getById('tx-1'), isNotNull);
    expect(find.text('Lunch'), findsOneWidget);

    // Delete confirms and removes the transaction.
    await tester.tap(find.byTooltip('Transaction options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(await transactions.getById('tx-1'), isNull);
    expect(find.text('Lunch'), findsNothing);
    expect(find.text('No transactions yet'), findsOneWidget);

    await database.close();
  });

  group('search and filter', () {
    /// Seeds two accounts, a category, and three transactions of different
    /// types so search/filter can be exercised meaningfully.
    Future<AppDatabase> pumpWithData(WidgetTester tester) async {
      final database = await pumpList(tester);
      final accounts = AccountDao(database);
      final categories = CategoryDao(database);
      final transactions = TransactionDao(database);

      await accounts.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-bank',
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
          id: 'cat-test-food',
          name: 'Groceries',
          type: CategoryType.expense,
        ),
      );
      await transactions.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-groceries',
          type: TransactionType.expense,
          amountMinor: 50000,
          accountId: 'acct-bank',
          categoryId: const Value('cat-test-food'),
          date: DateTime(2026, 8, 10),
          description: const Value('Weekly groceries'),
        ),
      );
      await transactions.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-salary',
          type: TransactionType.income,
          amountMinor: 1000000,
          accountId: 'acct-bank',
          date: DateTime(2026, 8, 9),
          description: const Value('Salary'),
        ),
      );
      await transactions.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-transfer',
          type: TransactionType.transfer,
          amountMinor: 250000,
          accountId: 'acct-bank',
          destinationAccountId: const Value('acct-cash'),
          date: DateTime(2026, 8, 8),
        ),
      );
      await tester.pumpAndSettle();
      return database;
    }

    testWidgets('typing in search narrows the list', (tester) async {
      final database = await pumpWithData(tester);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'salary');
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      expect(find.text('Transfer · Main Bank → Cash'), findsNothing);
      expect(find.text('1 of 3 transactions'), findsOneWidget);

      await database.close();
    });

    testWidgets('a search with no matches offers to clear it', (tester) async {
      final database = await pumpWithData(tester);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nonexistent merchant');
      await tester.pumpAndSettle();

      expect(find.text('No matching transactions'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Clear filters'));
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);

      await database.close();
    });

    testWidgets('closing search clears it and restores the full list', (
      tester,
    ) async {
      final database = await pumpWithData(tester);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'salary');
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsNothing);

      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);

      await database.close();
    });

    testWidgets('filtering by type shows only matching transactions', (
      tester,
    ) async {
      final database = await pumpWithData(tester);

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      expect(find.text('Filter transactions'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Income'));
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      expect(find.text('Transfer · Main Bank → Cash'), findsNothing);
      expect(find.text('1 of 3 transactions'), findsOneWidget);

      await database.close();
    });

    testWidgets('filtering by account shows only that account\'s activity', (
      tester,
    ) async {
      final database = await pumpWithData(tester);

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      // The transfer touches Cash as its destination.
      expect(find.text('Transfer · Main Bank → Cash'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);
      expect(find.text('Groceries'), findsNothing);

      await database.close();
    });

    testWidgets('the summary bar Clear button removes every filter', (
      tester,
    ) async {
      final database = await pumpWithData(tester);

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Income'));
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Transfer · Main Bank → Cash'), findsOneWidget);

      await database.close();
    });

    testWidgets('Clear inside the filter sheet keeps the active search', (
      tester,
    ) async {
      final database = await pumpWithData(tester);

      // Search for a term that matches both the salary and a filtered type,
      // so the interaction between search and structured filters is visible.
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Income'));
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Transfer · Main Bank → Cash'), findsNothing);

      // Clearing the structured filters should not clear the search text.
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Salary'), findsOneWidget);
      final searchField = tester.widget<TextField>(find.byType(TextField));
      expect(searchField.controller!.text, 'a');

      await database.close();
    });
  });
}
