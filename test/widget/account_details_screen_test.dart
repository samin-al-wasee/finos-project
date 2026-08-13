import 'package:drift/drift.dart';
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/data/credit_card_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/accounts/presentation/account_details_screen.dart';
import 'package:finos_app/features/accounts/presentation/account_form_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppDatabase> pumpDetails(
    WidgetTester tester, {
    required String id,
    required String name,
    AccountStatus status = AccountStatus.active,
  }) async {
    final database = AppDatabase.inMemory();
    final dao = AccountDao(database);
    await dao.insertOne(
      FinancialAccountsCompanion.insert(
        id: id,
        name: name,
        type: AccountType.bank,
        openingBalanceMinor: const Value(5000000),
        status: Value(status),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AccountDetailsScreen(accountId: id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  testWidgets('shows balance, currency, type and status', (tester) async {
    final database = await pumpDetails(tester, id: 'a1', name: 'Main Bank');

    expect(find.text('Main Bank'), findsOneWidget);
    expect(find.text('৳50,000.00'), findsOneWidget);
    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('BDT'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);

    await database.close();
  });

  testWidgets('shows live balance including transaction impact', (
    tester,
  ) async {
    final database = await pumpDetails(tester, id: 'a1', name: 'Main Bank');

    // Opening balance is shown before any transactions.
    expect(find.text('৳50,000.00'), findsOneWidget);

    final transactions = TransactionDao(database);
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-expense',
        type: TransactionType.expense,
        amountMinor: 500000,
        accountId: 'a1',
        date: DateTime.now(),
        description: const Value('Lunch'),
      ),
    );

    await tester.pumpAndSettle();

    // 50,000 - 5,000 = 45,000.00 — the live balance, not the opening balance.
    expect(find.text('৳45,000.00'), findsOneWidget);
    expect(find.text('৳50,000.00'), findsNothing);

    await database.close();
  });

  testWidgets('edit opens the account form in edit mode', (tester) async {
    final database = await pumpDetails(tester, id: 'a1', name: 'Main Bank');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountFormScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Edit account'), findsOneWidget);

    await database.close();
  });

  testWidgets('archive confirms, then archives the account', (tester) async {
    final database = await pumpDetails(tester, id: 'a1', name: 'Main Bank');
    final dao = AccountDao(database);

    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Archive'),
      ),
    );
    await tester.pumpAndSettle();

    expect((await dao.getById('a1'))!.status, AccountStatus.archived);
    expect(find.text('Account archived'), findsOneWidget);

    await database.close();
  });

  testWidgets('does not show a credit card section for a plain account', (
    tester,
  ) async {
    final database = await pumpDetails(tester, id: 'a1', name: 'Main Bank');

    expect(find.text('Credit limit'), findsNothing);

    await database.close();
  });

  testWidgets('shows the credit card cycle for a credit-card account', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    final accounts = AccountDao(database);
    final creditCards = CreditCardDao(database);
    final transactions = TransactionDao(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'a1',
        name: 'Visa',
        type: AccountType.creditCard,
      ),
    );
    // Anchoring the statement day on today's own day-of-month makes "today"
    // always exactly the previous statement date, regardless of which real
    // calendar date the test happens to run on.
    await creditCards.insertOne(
      CreditCardDetailsCompanion.insert(
        id: 'card-1',
        accountId: 'a1',
        creditLimitMinor: 10000000,
        statementDay: DateTime.now().day,
        paymentDueOffsetDays: 21,
      ),
    );
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-before',
        type: TransactionType.expense,
        amountMinor: 30000,
        accountId: 'a1',
        date: yesterday,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-after',
        type: TransactionType.expense,
        amountMinor: 10000,
        accountId: 'a1',
        date: DateTime.now(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AccountDetailsScreen(accountId: 'a1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Credit limit'), findsOneWidget);
    expect(find.text('৳100,000.00'), findsOneWidget);
    expect(find.text('Available credit'), findsOneWidget);
    expect(find.text('৳99,600.00'), findsOneWidget);
    expect(find.text('Current balance owed'), findsOneWidget);
    expect(find.text('৳400.00'), findsOneWidget);
    // Only yesterday's spend counts toward the already-closed statement.
    expect(find.textContaining('Previous statement ('), findsOneWidget);
    expect(find.text('৳300.00'), findsOneWidget);
    expect(find.text('Payment due'), findsOneWidget);

    await database.close();
  });

  testWidgets('archived account offers restore instead of archive', (
    tester,
  ) async {
    final database = await pumpDetails(
      tester,
      id: 'a1',
      name: 'Old Account',
      status: AccountStatus.archived,
    );
    final dao = AccountDao(database);

    expect(find.text('Archived'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Restore'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Archive'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();

    expect((await dao.getById('a1'))!.status, AccountStatus.active);
    expect(find.text('Account restored'), findsOneWidget);

    await database.close();
  });
}
