import 'package:drift/drift.dart' hide isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/loans/application/loan_controller.dart';
import 'package:finos_app/features/loans/data/loan_dao.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/net_worth/presentation/net_worth_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the Net Worth screen (docs/ROADMAP.md §9.1), reached
/// from Settings → Insights.
void main() {
  Future<AppDatabase> pumpNetWorth(WidgetTester tester) async {
    final database = AppDatabase.inMemory();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NetWorthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  testWidgets('shows an empty state with no accounts and no loans', (
    tester,
  ) async {
    final database = await pumpNetWorth(tester);

    expect(find.text('Nothing to show yet'), findsOneWidget);

    await database.close();
  });

  testWidgets(
    'shows assets and liabilities from accounts, credit cards, and loans',
    (tester) async {
      final database = AppDatabase.inMemory();
      final accounts = AccountDao(database);
      await accounts.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-bank',
          name: 'Main Bank',
          type: AccountType.bank,
          openingBalanceMinor: const Value(100000),
        ),
      );
      await accounts.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-card',
          name: 'Visa',
          type: AccountType.creditCard,
          openingBalanceMinor: const Value(-20000),
        ),
      );
      await LoanController(
        database,
        LoanDao(database),
        TransactionDao(database),
        AccountDao(database),
      ).create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 30000,
      );
      await LoanController(
        database,
        LoanDao(database),
        TransactionDao(database),
        AccountDao(database),
      ).create(
        direction: LoanDirection.borrowed,
        name: 'Car Loan',
        principalMinor: 50000,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const NetWorthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main Bank'), findsOneWidget);
      expect(find.text('John'), findsOneWidget);
      expect(find.text('Visa'), findsOneWidget);
      expect(find.text('Car Loan'), findsOneWidget);
      // Net worth = (100000 + 30000 assets) - (20000 + 50000 liabilities) = 60000.
      expect(find.text('৳600.00'), findsOneWidget);

      await database.close();
    },
  );
}
