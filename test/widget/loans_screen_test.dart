import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/loans/application/loan_controller.dart';
import 'package:finos_app/features/loans/data/loan_dao.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/loans/presentation/loan_details_screen.dart';
import 'package:finos_app/features/loans/presentation/loan_form_screen.dart';
import 'package:finos_app/features/loans/presentation/loans_list_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the Loans tab and detail screen (FR-06,
/// docs/UI_DESIGN.md §21–§22).
void main() {
  /// Creates a database with one active account to move loan money through.
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

  group('list', () {
    testWidgets('shows an empty state with no loans', (tester) async {
      final database = await seedDatabase();
      await pumpLoans(tester, database);

      expect(find.text('No loans yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add loan'), findsOneWidget);

      await database.close();
    });

    testWidgets('the empty state opens the loan form', (tester) async {
      final database = await seedDatabase();
      await pumpLoans(tester, database);

      await tester.tap(find.widgetWithText(FilledButton, 'Add loan'));
      await tester.pumpAndSettle();

      expect(find.byType(LoanFormScreen), findsOneWidget);

      await database.close();
    });

    testWidgets('separates money owed from money owed to me', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 25000000,
      );
      await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );

      await pumpLoans(tester, database);

      // The two directions are never mixed into one list
      // (docs/UI_DESIGN.md §21).
      expect(find.text('I Owe'), findsOneWidget);
      expect(find.text('Owed to Me'), findsOneWidget);
      expect(find.text('Bank Loan'), findsOneWidget);
      expect(find.text('John'), findsOneWidget);

      await database.close();
    });

    testWidgets('shows what remains and the standing in words', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 500000,
        accountId: 'acct-bank',
      );

      await pumpLoans(tester, database);

      expect(
        find.textContaining('৳15,000.00 remaining of ৳20,000.00'),
        findsOneWidget,
      );
      expect(find.textContaining('Outstanding'), findsOneWidget);

      await database.close();
    });

    testWidgets('marks a past-due loan as overdue', (tester) async {
      final database = await seedDatabase();
      await controllerFor(database).create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        startDate: DateTime(2020, 1, 1),
        dueDate: DateTime(2020, 6, 1),
      );

      await pumpLoans(tester, database);

      expect(find.textContaining('Overdue'), findsOneWidget);

      await database.close();
    });

    testWidgets(
      'a linked group renders as one tile with a "+N linked" indicator; '
      'tapping opens the primary member\'s details screen',
      (tester) async {
        final database = await seedDatabase();
        final controller = controllerFor(database);
        final rootId = await controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 2000000,
          startDate: DateTime(2026, 1, 1),
        );
        await controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 500000,
          startDate: DateTime(2026, 6, 1),
          extendsLoanId: rootId,
        );

        await pumpLoans(tester, database);

        // One tile, not two, with the "+1 linked" indicator.
        expect(find.text('John'), findsOneWidget);
        expect(find.text('+1 linked'), findsOneWidget);

        await tester.tap(find.text('John'));
        await tester.pumpAndSettle();

        expect(find.byType(LoanDetailsScreen), findsOneWidget);
        // The primary is the most recently started active member — the
        // ৳5,000 extension, not the original ৳20,000 loan.
        expect(find.text('Original amount'), findsOneWidget);
        expect(find.text('৳5,000.00'), findsWidgets);
        expect(find.text('৳20,000.00'), findsNothing);

        await database.close();
      },
    );

    testWidgets('marks a settled loan as fully repaid', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 2000000,
        accountId: 'acct-bank',
      );

      await pumpLoans(tester, database);

      expect(find.textContaining('Fully repaid'), findsOneWidget);

      await database.close();
    });
  });

  group('form', () {
    testWidgets('creates a loan without moving money', (tester) async {
      final database = await seedDatabase();
      await pumpLoans(tester, database);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Bank Loan');
      await tester.enterText(find.byType(TextFormField).at(1), '25000');
      await tester.tap(find.widgetWithText(FilledButton, 'Add loan'));
      await tester.pumpAndSettle();

      final loans = await LoanDao(database).getAll();
      expect(loans, hasLength(1));
      expect(loans.single.name, 'Bank Loan');
      expect(loans.single.principalMinor, 2500000);
      // No disbursement account chosen, so no cash moved.
      expect(loans.single.disbursementAccountId, isNull);
      expect(await TransactionDao(database).getAll(), isEmpty);

      await database.close();
    });

    testWidgets('requires a name', (tester) async {
      final database = await seedDatabase();
      await pumpLoans(tester, database);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), '25000');
      await tester.tap(find.widgetWithText(FilledButton, 'Add loan'));
      await tester.pumpAndSettle();

      expect(find.text('Enter who the loan is with'), findsOneWidget);
      expect(await LoanDao(database).getAll(), isEmpty);

      await database.close();
    });

    testWidgets('requires a positive amount', (tester) async {
      final database = await seedDatabase();
      await pumpLoans(tester, database);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Bank Loan');
      await tester.enterText(find.byType(TextFormField).at(1), '0');
      await tester.tap(find.widgetWithText(FilledButton, 'Add loan'));
      await tester.pumpAndSettle();

      expect(find.text('Amount must be greater than zero'), findsOneWidget);
      expect(await LoanDao(database).getAll(), isEmpty);

      await database.close();
    });

    testWidgets('creating with a disbursement account moves the money', (
      tester,
    ) async {
      final database = await seedDatabase();
      await pumpLoans(tester, database);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Bank Loan');
      await tester.enterText(find.byType(TextFormField).at(1), '25000');

      // Pick the account the money arrives in. The "Link to an existing loan"
      // picker is the first dropdown on the create form, so the disbursement
      // picker is the last one.
      await tester.tap(find.byType(DropdownButtonFormField<String?>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Bank').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add loan'));
      await tester.pumpAndSettle();

      // Borrowing adds to the account.
      expect(
        await TransactionDao(database).balanceImpactFor('acct-bank'),
        2500000,
      );

      await database.close();
    });

    testWidgets(
      'the "Link to an existing loan" picker lists only active loans of the '
      'matching direction, and selecting one pre-fills the name field',
      (tester) async {
        final database = await seedDatabase();
        final controller = controllerFor(database);
        await controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 2000000,
        );
        final archivedId = await controller.create(
          direction: LoanDirection.lent,
          name: 'Old Friend',
          principalMinor: 100000,
        );
        await controller.archive(archivedId);
        await controller.create(
          direction: LoanDirection.borrowed,
          name: 'Other Bank',
          principalMinor: 500000,
        );

        await pumpLoans(tester, database);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        // Default direction is "borrowed"; switch to "lent" to match John's
        // and the archived loan's direction.
        await tester.tap(find.text('Money I lent'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
        await tester.pumpAndSettle();

        expect(find.textContaining('John ·'), findsOneWidget);
        expect(find.textContaining('Old Friend'), findsNothing);
        expect(find.textContaining('Other Bank'), findsNothing);

        await tester.tap(find.textContaining('John ·').last);
        await tester.pumpAndSettle();

        final nameField = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(nameField.controller!.text, 'John');

        await database.close();
      },
    );
  });

  group('details', () {
    Future<void> pumpDetails(
      WidgetTester tester,
      AppDatabase database,
      String loanId,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: LoanDetailsScreen(loanId: loanId),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows original, paid, and remaining', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 1200000,
        accountId: 'acct-bank',
      );

      await pumpDetails(tester, database, id);

      // The figures from docs/UI_DESIGN.md §22.
      expect(find.text('John'), findsOneWidget);
      expect(find.text('Owed to me'), findsOneWidget);
      expect(find.text('Original amount'), findsOneWidget);
      expect(find.text('৳20,000.00'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      // Appears twice: once in the Paid row and once as the repayment in the
      // activity list below.
      expect(find.text('৳12,000.00'), findsWidgets);
      expect(find.text('Remaining'), findsOneWidget);
      expect(find.text('৳8,000.00'), findsOneWidget);

      await database.close();
    });

    testWidgets('lists the recorded repayments', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 500000,
        accountId: 'acct-bank',
      );

      await pumpDetails(tester, database, id);

      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Lent to John'), findsOneWidget);
      expect(find.text('Repayment · John'), findsOneWidget);

      await database.close();
    });

    testWidgets('recording a repayment updates the figures and balance', (
      tester,
    ) async {
      final database = await seedDatabase();
      final id = await controllerFor(database).create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 2000000,
      );

      await pumpDetails(tester, database, id);
      expect(find.text('৳0.00'), findsOneWidget); // nothing paid yet

      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      // The dialog pre-fills the full outstanding amount.
      await tester.enterText(find.byType(TextFormField).last, '500');
      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pumpAndSettle();

      expect(find.text('Repayment recorded'), findsOneWidget);
      // Paid ৳500, so ৳19,500 remains.
      expect(find.text('৳19,500.00'), findsOneWidget);
      expect(
        await TransactionDao(database).balanceImpactFor('acct-bank'),
        -50000,
      );

      await database.close();
    });

    testWidgets('refuses a repayment larger than what is outstanding', (
      tester,
    ) async {
      final database = await seedDatabase();
      final id = await controllerFor(database).create(
        direction: LoanDirection.borrowed,
        name: 'Bank Loan',
        principalMinor: 2000000,
      );

      await pumpDetails(tester, database, id);
      await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).last, '99999');
      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pumpAndSettle();

      // Caught in the dialog, so the user sees it before anything is written
      // (docs/DATA_MODEL.md §36).
      expect(
        find.text('That is more than the outstanding amount'),
        findsOneWidget,
      );
      expect(await TransactionDao(database).getAll(), isEmpty);

      await database.close();
    });

    testWidgets('offers no repayment button once fully repaid', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 2000000,
        accountId: 'acct-bank',
      );

      await pumpDetails(tester, database, id);

      expect(find.text('Fully repaid'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Record receipt'), findsNothing);

      await database.close();
    });

    testWidgets('Related loans lists siblings and navigates to each one\'s own '
        'details screen', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final rootId = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        startDate: DateTime(2026, 1, 1),
      );
      await controller.create(
        direction: LoanDirection.lent,
        name: 'Jane',
        principalMinor: 500000,
        startDate: DateTime(2026, 6, 1),
        extendsLoanId: rootId,
      );

      await pumpDetails(tester, database, rootId);

      expect(find.text('Related loans'), findsOneWidget);
      expect(
        find.textContaining('Combined outstanding across 2 linked loans'),
        findsOneWidget,
      );
      expect(find.text('Jane'), findsOneWidget);

      await tester.tap(find.text('Jane'));
      await tester.pumpAndSettle();

      // Now looking at Jane's own details screen.
      expect(find.text('Jane'), findsOneWidget);
      expect(find.text('Owed to me'), findsOneWidget);
      expect(find.text('Original amount'), findsOneWidget);
      expect(find.text('৳5,000.00'), findsWidgets);

      await database.close();
    });

    testWidgets(
      '"Extend" is visible on an active loan regardless of paid status, and '
      'hidden once archived',
      (tester) async {
        final database = await seedDatabase();
        final controller = controllerFor(database);
        final id = await controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 2000000,
        );
        await controller.recordRepayment(
          loanId: id,
          amountMinor: 2000000,
          accountId: 'acct-bank',
        );

        await pumpDetails(tester, database, id);
        expect(find.text('Fully repaid'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Extend'), findsOneWidget);

        await controller.archive(id);
        await pumpDetails(tester, database, id);
        expect(find.widgetWithText(OutlinedButton, 'Extend'), findsNothing);

        await database.close();
      },
    );

    testWidgets('tapping Extend opens the form in extend mode', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );

      await pumpDetails(tester, database, id);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Extend'));
      await tester.pumpAndSettle();

      expect(find.byType(LoanFormScreen), findsOneWidget);
      expect(find.text('Extend loan'), findsWidgets);
      // The direction selector is hidden and the name is pre-filled.
      expect(find.byType(SegmentedButton<LoanDirection>), findsNothing);
      final nameField = tester.widget<TextFormField>(
        find.byType(TextFormField).first,
      );
      expect(nameField.controller!.text, 'John');

      await database.close();
    });

    testWidgets('deleting a loan with repayments is refused', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 500000,
        accountId: 'acct-bank',
      );

      await pumpDetails(tester, database, id);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Archive it instead'), findsOneWidget);
      expect(await LoanDao(database).getById(id), isNotNull);

      await database.close();
    });
  });
}
