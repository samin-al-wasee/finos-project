import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/accounts/presentation/account_form_screen.dart';
import 'package:finos_app/features/loans/application/loan_controller.dart';
import 'package:finos_app/features/loans/data/loan_dao.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/loans/presentation/repayment_dialog.dart';
import 'package:finos_app/features/quick_entry/presentation/quick_entry_bar.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/presentation/transaction_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for [QuickEntryBar] — the terminal-style global shortcut for
/// recording any write operation (docs/ARCHITECTURE.md, "quick entry"). These
/// cover the wiring end-to-end (typed text -> the right screen or dialog,
/// pre-filled); [resolveQuickCommand]'s own field-by-field mapping is
/// covered more exhaustively by quick_command_resolver_test.dart.
void main() {
  Future<AppDatabase> pumpBar(WidgetTester tester) async {
    final database = AppDatabase.inMemory();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: QuickEntryBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  testWidgets('"@" shows the top-level commands, scrollable to the rest', (
    tester,
  ) async {
    final database = await pumpBar(tester);

    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();

    // The suggestion panel is height-bounded, so only the first few of the
    // eleven commands are mounted without scrolling — the same lazy-mounting
    // behaviour the transaction list itself relies on for large lists.
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);

    final last = find.text('New recurring rule');
    for (var i = 0; i < 20 && last.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pump();
    }
    expect(last, findsOneWidget);

    await database.close();
  });

  testWidgets('"@inc" filters the top-level list', (tester) async {
    final database = await pumpBar(tester);

    await tester.enterText(find.byType(TextField), '@inc');
    await tester.pump();

    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Expense'), findsNothing);

    await database.close();
  });

  testWidgets('picking a top-level suggestion fills the command word', (
    tester,
  ) async {
    final database = await pumpBar(tester);

    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();
    await tester.tap(find.text('Income'));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Income ',
    );

    await database.close();
  });

  testWidgets(
    'shows a fading hint for the active field, gone once it\'s typed',
    (tester) async {
      final database = await pumpBar(tester);

      await tester.enterText(find.byType(TextField), 'income ');
      await tester.pump();
      expect(find.text('income <amount>'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'income 5');
      await tester.pump();
      expect(find.text('income <amount>'), findsNothing);

      await tester.enterText(find.byType(TextField), 'income 500 ');
      await tester.pump();
      expect(find.text('income 500 <date>'), findsOneWidget);

      await database.close();
    },
  );

  testWidgets('"@" inside a chosen command suggests that field\'s accounts', (
    tester,
  ) async {
    final database = await pumpBar(tester);
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'income 500 today @');
    await tester.pump();

    expect(find.text('Main Bank'), findsOneWidget);

    await database.close();
  });

  testWidgets('a full income command opens the transaction form, pre-filled', (
    tester,
  ) async {
    final database = await pumpBar(tester);
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'income 500 today "Main Bank"',
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionFormScreen), findsOneWidget);
    expect(find.text('500'), findsOneWidget);

    await database.close();
  });

  testWidgets('an account name that matches nothing shows an error', (
    tester,
  ) async {
    final database = await pumpBar(tester);

    await tester.enterText(
      find.byType(TextField),
      'expense 500 today "Nowhere"',
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.textContaining('No account named'), findsOneWidget);
    expect(find.byType(TransactionFormScreen), findsNothing);

    await database.close();
  });

  testWidgets('the send button is disabled until required fields are filled', (
    tester,
  ) async {
    final database = await pumpBar(tester);

    await tester.enterText(find.byType(TextField), 'income');
    await tester.pump();
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );

    await database.close();
  });

  testWidgets('a new-account command opens the account form, pre-filled', (
    tester,
  ) async {
    final database = await pumpBar(tester);

    await tester.enterText(find.byType(TextField), 'account Savings');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.byType(AccountFormScreen), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);

    await database.close();
  });

  testWidgets(
    'a repay command opens the repayment dialog, and confirming records it',
    (tester) async {
      final database = await pumpBar(tester);
      await AccountDao(database).insertOne(
        FinancialAccountsCompanion.insert(
          id: 'acct-bank',
          name: 'Main Bank',
          type: AccountType.bank,
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
        principalMinor: 100000,
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'repay John');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.byType(RepaymentDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pumpAndSettle();

      expect(find.text('Repayment recorded'), findsOneWidget);

      await database.close();
    },
  );

  testWidgets('an unrecognized loan name shows an error', (tester) async {
    final database = await pumpBar(tester);

    await tester.enterText(find.byType(TextField), 'repay Nobody');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.textContaining('No outstanding loan named'), findsOneWidget);

    await database.close();
  });
}
