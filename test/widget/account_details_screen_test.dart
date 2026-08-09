import 'package:drift/drift.dart';
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/accounts/presentation/account_details_screen.dart';
import 'package:finos_app/features/accounts/presentation/account_form_screen.dart';
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
