import 'package:drift/drift.dart' hide isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/loans/application/loan_controller.dart';
import 'package:finos_app/features/loans/data/loan_dao.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/loans/presentation/loan_details_screen.dart';
import 'package:finos_app/features/loans/presentation/loans_list_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the Loans tab's card view: a swipeable single-loan card
/// with a live repayment feed below it, toggled alongside (not replacing)
/// the existing list view, in the same "I Owe" before "Owed to Me" order
/// (docs/UI_DESIGN.md §21).
void main() {
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

  LoanController controllerFor(AppDatabase database) => LoanController(
    database,
    LoanDao(database),
    TransactionDao(database),
    AccountDao(database),
  );

  Future<void> pumpLoans(WidgetTester tester, AppDatabase database) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LoansListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the view toggle is hidden when there are no active loans', (
    tester,
  ) async {
    final database = await seedDatabase();
    await pumpLoans(tester, database);

    expect(find.byIcon(Icons.view_carousel), findsNothing);

    await database.close();
  });

  testWidgets('the toggle switches between list view and card view, and back', (
    tester,
  ) async {
    final database = await seedDatabase();
    await controllerFor(database).create(
      direction: LoanDirection.lent,
      name: 'John',
      principalMinor: 20000,
    );
    await pumpLoans(tester, database);

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
    'swiping moves borrowed-then-lent and updates the feed to that loan only',
    (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final bankLoanId = await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 500000,
      );
      await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 20000,
      );
      await controller.recordRepayment(
        loanId: bankLoanId,
        amountMinor: 10000,
        accountId: 'acct-bank',
        date: DateTime.now(),
      );
      await pumpLoans(tester, database);

      await tester.tap(find.byIcon(Icons.view_carousel));
      await tester.pumpAndSettle();

      // First page: the borrowed loan (I Owe), with its own repayment.
      expect(find.text('Bank Loan'), findsWidgets);
      expect(find.text('I Owe'), findsWidgets);
      expect(find.text('No repayments recorded yet'), findsNothing);

      await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();

      // Second page: the lent loan (Owed to Me), with no repayments yet.
      expect(find.text('John'), findsWidgets);
      expect(find.text('Owed to Me'), findsWidgets);
      expect(find.text('No repayments recorded yet'), findsOneWidget);

      await database.close();
    },
  );

  testWidgets(
    'an extended loan shows the linked indicator and resolves via the primary member',
    (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final rootId = await controller.create(
        direction: LoanDirection.lent,
        name: 'Alice',
        principalMinor: 10000,
      );
      await controller.create(
        direction: LoanDirection.lent,
        name: 'Alice',
        principalMinor: 5000,
        extendsLoanId: rootId,
      );
      await pumpLoans(tester, database);

      await tester.tap(find.byIcon(Icons.view_carousel));
      await tester.pumpAndSettle();

      expect(find.text('+1 linked'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await database.close();
    },
  );

  testWidgets('tapping a card opens the existing Loan Details screen', (
    tester,
  ) async {
    final database = await seedDatabase();
    await controllerFor(database).create(
      direction: LoanDirection.lent,
      name: 'John',
      principalMinor: 20000,
    );
    await pumpLoans(tester, database);

    await tester.tap(find.byIcon(Icons.view_carousel));
    await tester.pumpAndSettle();

    await tester.tap(find.text('John').first);
    await tester.pumpAndSettle();

    expect(find.byType(LoanDetailsScreen), findsOneWidget);

    await database.close();
  });
}
