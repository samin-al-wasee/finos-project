import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/transactions/presentation/transaction_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trivial host screen that pushes [TransactionFormScreen] on the first frame.
///
/// Popping the form returns to this scaffold, so pumpAndSettle finishes cleanly.
class _FormHost extends StatefulWidget {
  const _FormHost();

  @override
  State<_FormHost> createState() => _FormHostState();
}

class _FormHostState extends State<_FormHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TransactionFormScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

void main() {
  Future<AppDatabase> pumpForm(WidgetTester tester) async {
    final database = AppDatabase.inMemory();

    // Seed one active account so the form has something to select.
    final dao = AccountDao(database);
    await dao.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(theme: AppTheme.light(), home: const _FormHost()),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  testWidgets('shows the type selector with three options', (tester) async {
    final database = await pumpForm(tester);

    expect(find.widgetWithText(AppBar, 'Add transaction'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);

    await database.close();
  });

  testWidgets('requires an amount', (tester) async {
    final database = await pumpForm(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
    await tester.pump();

    expect(find.text('Enter an amount'), findsOneWidget);

    await database.close();
  });

  testWidgets('rejects a zero amount', (tester) async {
    final database = await pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
    await tester.pump();

    expect(find.text('Amount must be greater than zero'), findsOneWidget);

    await database.close();
  });

  testWidgets('shows the "To" dropdown only for transfers', (tester) async {
    final database = await pumpForm(tester);

    // Default is expense — "To" should not appear.
    expect(find.text('To'), findsNothing);

    // Switch to transfer.
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    expect(find.text('To'), findsOneWidget);

    // Switch back to expense — "To" disappears.
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();

    expect(find.text('To'), findsNothing);

    await database.close();
  });

  testWidgets('form is scrollable to reach the save button', (tester) async {
    final database = await pumpForm(tester);

    // Enter amount so validation passes.
    await tester.enterText(find.byType(TextFormField).first, '100');

    // The save button should be reachable via scrolling.
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Add transaction'),
      100,
      scrollable: find.byType(Scrollable).first,
    );

    await database.close();
  });
}
