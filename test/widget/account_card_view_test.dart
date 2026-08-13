import 'package:drift/drift.dart' hide isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/accounts/presentation/account_details_screen.dart';
import 'package:finos_app/features/accounts/presentation/accounts_list_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the Accounts tab's card view (docs/UI_DESIGN.md §31):
/// a swipeable single-account card with a live transaction feed below it,
/// toggled alongside (not replacing) the existing list view.
void main() {
  Future<AppDatabase> pumpAccounts(
    WidgetTester tester, {
    List<FinancialAccountsCompanion> seed = const [],
  }) async {
    final database = AppDatabase.inMemory();
    final dao = AccountDao(database);
    for (final entry in seed) {
      await dao.insertOne(entry);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AccountsListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  FinancialAccountsCompanion seedAccount(
    String id,
    String name, {
    AccountType type = AccountType.bank,
    int balance = 0,
    AccountStatus status = AccountStatus.active,
  }) {
    return FinancialAccountsCompanion.insert(
      id: id,
      name: name,
      type: type,
      openingBalanceMinor: Value(balance),
      status: Value(status),
    );
  }

  testWidgets('the view toggle is hidden when there are no active accounts', (
    tester,
  ) async {
    final database = await pumpAccounts(tester);

    expect(find.byIcon(Icons.view_carousel), findsNothing);

    await database.close();
  });

  testWidgets('the toggle switches between list view and card view, and back', (
    tester,
  ) async {
    final database = await pumpAccounts(
      tester,
      seed: [seedAccount('acct-1', 'Main Bank')],
    );

    // List view is the default.
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
    'swiping shows the next account and its own transaction feed only',
    (tester) async {
      final database = await pumpAccounts(
        tester,
        seed: [
          seedAccount('acct-1', 'Main Bank', balance: 100000),
          seedAccount('acct-2', 'Cash', balance: 50000),
        ],
      );
      final transactions = TransactionDao(database);
      await transactions.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-1',
          type: TransactionType.expense,
          amountMinor: 2000,
          accountId: 'acct-1',
          date: DateTime.now(),
          description: const Value('Bank expense'),
        ),
      );
      await transactions.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-2',
          type: TransactionType.expense,
          amountMinor: 3000,
          accountId: 'acct-2',
          date: DateTime.now(),
          description: const Value('Cash expense'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.view_carousel));
      await tester.pumpAndSettle();

      // First page: Main Bank and only its own transaction.
      expect(find.text('Main Bank'), findsWidgets);
      expect(find.text('Bank expense'), findsOneWidget);
      expect(find.text('Cash expense'), findsNothing);

      await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();

      // Second page: Cash and only its own transaction.
      expect(find.text('Cash'), findsWidgets);
      expect(find.text('Cash expense'), findsOneWidget);
      expect(find.text('Bank expense'), findsNothing);

      await database.close();
    },
  );

  testWidgets('a transfer into the selected account appears in its feed', (
    tester,
  ) async {
    final database = await pumpAccounts(
      tester,
      seed: [seedAccount('acct-1', 'Main Bank'), seedAccount('acct-2', 'Cash')],
    );
    final transactions = TransactionDao(database);
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-transfer',
        type: TransactionType.transfer,
        amountMinor: 5000,
        accountId: 'acct-1',
        destinationAccountId: const Value('acct-2'),
        date: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.view_carousel));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();

    // Cash is the destination side of the transfer, so it still shows up
    // in Cash's own feed.
    expect(find.textContaining('Transfer'), findsOneWidget);

    await database.close();
  });

  testWidgets('an account with no transactions shows an empty state', (
    tester,
  ) async {
    final database = await pumpAccounts(
      tester,
      seed: [seedAccount('acct-1', 'Main Bank')],
    );

    await tester.tap(find.byIcon(Icons.view_carousel));
    await tester.pumpAndSettle();

    expect(find.text('No transactions yet'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await database.close();
  });

  testWidgets('tapping a card opens the existing Account Details screen', (
    tester,
  ) async {
    final database = await pumpAccounts(
      tester,
      seed: [seedAccount('acct-1', 'Main Bank')],
    );

    await tester.tap(find.byIcon(Icons.view_carousel));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Main Bank').first);
    await tester.pumpAndSettle();

    expect(find.byType(AccountDetailsScreen), findsOneWidget);

    await database.close();
  });
}
