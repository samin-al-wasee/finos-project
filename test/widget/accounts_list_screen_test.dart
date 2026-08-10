import 'package:drift/drift.dart';
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/accounts/presentation/account_form_screen.dart';
import 'package:finos_app/features/accounts/presentation/accounts_list_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppDatabase> pumpList(
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

  FinancialAccountsCompanion seedRow(
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

  testWidgets(
    'shows an empty state with an add action when there are no accounts',
    (tester) async {
      final database = await pumpList(tester);

      expect(find.text('No accounts yet'), findsOneWidget);
      expect(find.text('Add account'), findsWidgets);

      await database.close();
    },
  );

  testWidgets('renders account tiles with names and balances', (tester) async {
    final database = await pumpList(
      tester,
      seed: [
        seedRow('a1', 'Main Bank', type: AccountType.bank, balance: 5000000),
        seedRow('a2', 'bKash', type: AccountType.mfs, balance: 250050),
      ],
    );

    expect(find.text('Main Bank'), findsOneWidget);
    expect(find.text('৳50,000.00'), findsOneWidget);
    expect(find.text('bKash'), findsOneWidget);
    expect(find.text('৳2,500.50'), findsOneWidget);
    // No archived section when nothing is archived.
    expect(find.text('Archived'), findsNothing);

    await database.close();
  });

  testWidgets('account balances reflect transaction activity', (tester) async {
    final database = await pumpList(
      tester,
      seed: [
        seedRow('a1', 'Main Bank', type: AccountType.bank, balance: 1000000),
      ],
    );

    // Opening balance is shown before any transactions.
    expect(find.text('৳10,000.00'), findsOneWidget);

    final transactions = TransactionDao(database);
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-expense',
        type: TransactionType.expense,
        amountMinor: 250000,
        accountId: 'a1',
        date: DateTime.now(),
        description: const Value('Lunch'),
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-income',
        type: TransactionType.income,
        amountMinor: 500000,
        accountId: 'a1',
        date: DateTime.now(),
        description: const Value('Salary'),
      ),
    );

    await tester.pumpAndSettle();

    // 10,000 + 5,000 - 2,500 = 12,500.00 — the live balance, not the opening
    // balance.
    expect(find.text('৳12,500.00'), findsOneWidget);
    expect(find.text('৳10,000.00'), findsNothing);

    await database.close();
  });

  testWidgets('groups archived accounts under an Archived header', (
    tester,
  ) async {
    final database = await pumpList(
      tester,
      seed: [
        seedRow('a1', 'Active Account'),
        seedRow('a2', 'Old Account', status: AccountStatus.archived),
      ],
    );

    expect(find.text('Active Account'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Old Account'), findsOneWidget);

    await database.close();
  });

  testWidgets('floating action button opens the account form', (tester) async {
    final database = await pumpList(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(AccountFormScreen), findsOneWidget);

    await database.close();
  });

  testWidgets('empty-state add button opens the account form', (tester) async {
    final database = await pumpList(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountFormScreen), findsOneWidget);

    await database.close();
  });
}
