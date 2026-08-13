import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/data/credit_card_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/accounts/presentation/account_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trivial host screen that pushes [AccountFormScreen] on the first frame.
///
/// Popping the form returns to this scaffold, so pumpAndSettle finishes cleanly.
class _FormHost extends StatefulWidget {
  const _FormHost({this.initial});

  final FinancialAccountRow? initial;

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
        MaterialPageRoute<void>(
          builder: (_) => AccountFormScreen(initial: widget.initial),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

void main() {
  Future<AppDatabase> pumpForm(
    WidgetTester tester, {
    FinancialAccountRow? initial,
  }) async {
    final database = AppDatabase.inMemory();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: _FormHost(initial: initial),
        ),
      ),
    );
    await tester.pumpAndSettle(); // triggers the post-frame push
    return database;
  }

  testWidgets('requires an account name', (tester) async {
    final database = await pumpForm(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
    await tester.pump();

    expect(find.text('Enter an account name'), findsOneWidget);

    await database.close();
  });

  testWidgets('rejects a non-numeric opening balance', (tester) async {
    final database = await pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Main Bank');
    await tester.enterText(find.byType(TextFormField).at(1), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
    await tester.pump();

    expect(find.text('Enter a valid amount'), findsOneWidget);

    await database.close();
  });

  testWidgets('creates an account and persists it', (tester) async {
    final database = await pumpForm(tester);
    final dao = AccountDao(database);

    await tester.enterText(find.byType(TextFormField).at(0), 'Main Bank');
    await tester.enterText(find.byType(TextFormField).at(1), '50,000.00');
    await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
    await tester.pumpAndSettle();

    // Form should have popped back to the host.
    expect(find.byType(AccountFormScreen), findsNothing);

    final rows = await dao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Main Bank');
    expect(rows.single.type, AccountType.bank);
    expect(rows.single.currency, 'BDT');
    expect(rows.single.openingBalanceMinor, 5000000);

    await database.close();
  });

  testWidgets('pre-fills values in edit mode', (tester) async {
    final database = AppDatabase.inMemory();
    final dao = AccountDao(database);
    await dao.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'a1',
        name: 'Main Bank',
        type: AccountType.bank,
        currency: Value('USD'),
        openingBalanceMinor: Value(250000),
      ),
    );
    final row = (await dao.getById('a1'))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: _FormHost(initial: row),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Edit account'), findsOneWidget);
    expect(find.text('Main Bank'), findsOneWidget);
    expect(find.text('2500'), findsOneWidget);

    await database.close();
  });

  testWidgets('saves edits to an existing account', (tester) async {
    final database = AppDatabase.inMemory();
    final dao = AccountDao(database);
    await dao.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'a1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    final row = (await dao.getById('a1'))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: _FormHost(initial: row),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Primary Bank');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountFormScreen), findsNothing);

    final updated = await dao.getById('a1');
    expect(updated!.name, 'Primary Bank');

    await database.close();
  });

  group('credit card', () {
    Future<void> selectCreditCardType(WidgetTester tester) async {
      await tester.tap(find.byType(DropdownButtonFormField<AccountType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credit Card').last);
      await tester.pumpAndSettle();
    }

    testWidgets('reveals billing fields only once selected', (tester) async {
      final database = await pumpForm(tester);

      expect(find.text('Credit limit'), findsNothing);
      await selectCreditCardType(tester);
      expect(find.text('Credit limit'), findsOneWidget);
      expect(find.text('Statement closes on'), findsOneWidget);
      expect(find.text('Payment due'), findsOneWidget);

      await database.close();
    });

    testWidgets('requires a credit limit and payment due offset', (
      tester,
    ) async {
      final database = await pumpForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Visa');
      await selectCreditCardType(tester);
      // Payment due already carries a default, so clear it to hit that
      // validator too.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Payment due'),
        '',
      );
      // The credit-card fields push "Add account" beyond the ListView's
      // initially-built range.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
      await tester.pump();

      expect(find.text('Enter a credit limit'), findsOneWidget);
      expect(
        find.text('Enter how many days after the statement'),
        findsOneWidget,
      );

      await database.close();
    });

    testWidgets('creates the account and its billing details together', (
      tester,
    ) async {
      final database = await pumpForm(tester);
      final accounts = AccountDao(database);
      final creditCards = CreditCardDao(database);

      await tester.enterText(find.byType(TextFormField).at(0), 'Visa');
      await selectCreditCardType(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Credit limit'),
        '100,000.00',
      );
      // The credit-card fields push "Add account" beyond the ListView's
      // initially-built range.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add account'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountFormScreen), findsNothing);

      final account = (await accounts.getAll()).single;
      expect(account.name, 'Visa');
      expect(account.type, AccountType.creditCard);

      final details = await creditCards.getByAccountId(account.id);
      expect(details, isNotNull);
      expect(details!.creditLimitMinor, 10000000);
      expect(details.paymentDueOffsetDays, 21);

      await database.close();
    });

    testWidgets('pre-fills billing details in edit mode and locks the type', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      final accounts = AccountDao(database);
      final creditCards = CreditCardDao(database);
      await accounts.insertOne(
        FinancialAccountsCompanion.insert(
          id: 'a1',
          name: 'Visa',
          type: AccountType.creditCard,
        ),
      );
      await creditCards.insertOne(
        CreditCardDetailsCompanion.insert(
          id: 'card-1',
          accountId: 'a1',
          creditLimitMinor: 5000000,
          statementDay: 12,
          paymentDueOffsetDays: 18,
        ),
      );
      final row = (await accounts.getById('a1'))!;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: _FormHost(initial: row),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('50000'), findsOneWidget); // credit limit
      expect(find.text('Day 12'), findsOneWidget);
      expect(find.text('18'), findsOneWidget); // payment due offset

      // Only "Credit Card" is offered once an account already is one.
      await tester.tap(find.byType(DropdownButtonFormField<AccountType>));
      await tester.pumpAndSettle();
      expect(find.text('Bank'), findsNothing);
      expect(find.text('Credit Card'), findsWidgets);

      await database.close();
    });
  });
}
