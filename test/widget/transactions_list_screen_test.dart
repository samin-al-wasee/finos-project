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
}
