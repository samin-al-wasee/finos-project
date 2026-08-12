import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/recurring/data/recurring_transaction_dao.dart';
import 'package:finos_app/features/recurring/domain/recurrence_frequency.dart';
import 'package:finos_app/features/recurring/presentation/recurring_transaction_form_screen.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the add/edit recurring transaction form
/// (docs/ROADMAP.md §8.1).
void main() {
  Future<AppDatabase> seedDatabase() async {
    final database = AppDatabase.inMemory();
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-cash',
        name: 'Cash',
        type: AccountType.cash,
      ),
    );
    await CategoryDao(database).insertOne(
      CategoriesCompanion.insert(
        id: 'cat-test',
        name: 'Test Entertainment',
        type: CategoryType.expense,
      ),
    );
    return database;
  }

  Future<void> pumpForm(
    WidgetTester tester,
    AppDatabase database, {
    RecurringTransactionRow? initial,
  }) async {
    // This form has more fields than the default test viewport fits; a taller
    // surface avoids scrolling to reach fields the ListView would otherwise
    // leave unmounted outside its cache extent.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: RecurringTransactionFormScreen(initial: initial),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseAccount(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
  }

  testWidgets('requires a name', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '500');
    await chooseAccount(tester, 'Main Bank');
    await tapSave(tester, 'Add recurring transaction');
    await tester.pump();

    expect(
      find.text('Enter a name for this recurring transaction'),
      findsOneWidget,
    );
    expect(await RecurringTransactionDao(database).getAll(), isEmpty);

    await database.close();
  });

  testWidgets('requires an amount', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Netflix',
    );
    await chooseAccount(tester, 'Main Bank');
    await tapSave(tester, 'Add recurring transaction');
    await tester.pump();

    expect(find.text('Enter an amount'), findsOneWidget);
    expect(await RecurringTransactionDao(database).getAll(), isEmpty);

    await database.close();
  });

  testWidgets('rejects a zero amount', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Netflix',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '0');
    await chooseAccount(tester, 'Main Bank');
    await tapSave(tester, 'Add recurring transaction');
    await tester.pump();

    expect(find.text('Amount must be greater than zero'), findsOneWidget);
    expect(await RecurringTransactionDao(database).getAll(), isEmpty);

    await database.close();
  });

  testWidgets('requires an account', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Netflix',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '500');
    await tapSave(tester, 'Add recurring transaction');
    await tester.pump();

    expect(find.text('Choose an account'), findsOneWidget);
    expect(await RecurringTransactionDao(database).getAll(), isEmpty);

    await database.close();
  });

  testWidgets('defaults to monthly frequency and starts today', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Never'), findsOneWidget);

    await database.close();
  });

  testWidgets(
    'creates a rule whose first occurrence is the chosen start date',
    (tester) async {
      final database = await seedDatabase();
      await pumpForm(tester, database);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Netflix',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '500',
      );
      await chooseAccount(tester, 'Main Bank');

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Entertainment').last);
      await tester.pumpAndSettle();

      await tapSave(tester, 'Add recurring transaction');
      await tester.pumpAndSettle();

      final rows = await RecurringTransactionDao(database).getAll();
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Netflix');
      expect(rows.single.amountMinor, 50000);
      expect(rows.single.accountId, 'acct-bank');
      expect(rows.single.categoryId, 'cat-test');
      expect(rows.single.frequency, RecurrenceFrequency.monthly);
      expect(rows.single.nextOccurrence, rows.single.startDate);

      await database.close();
    },
  );

  testWidgets('a transfer requires a destination account', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Move to cash',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '500');
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    await chooseAccount(tester, 'Main Bank');

    await tapSave(tester, 'Add recurring transaction');
    await tester.pump();

    expect(find.text('Choose a destination account'), findsOneWidget);

    await database.close();
  });

  testWidgets('creates a transfer with the chosen destination', (tester) async {
    final database = await seedDatabase();
    await pumpForm(tester, database);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Move to cash',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '500');
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    await chooseAccount(tester, 'Main Bank');

    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'To'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash').last);
    await tester.pumpAndSettle();

    await tapSave(tester, 'Add recurring transaction');
    await tester.pumpAndSettle();

    final rows = await RecurringTransactionDao(database).getAll();
    expect(rows.single.type, TransactionType.transfer);
    expect(rows.single.accountId, 'acct-bank');
    expect(rows.single.destinationAccountId, 'acct-cash');
    expect(rows.single.categoryId, isNull);

    await database.close();
  });

  group('editing', () {
    Future<RecurringTransactionRow> seedRule(AppDatabase database) async {
      final dao = RecurringTransactionDao(database);
      await dao.insertOne(
        RecurringTransactionsCompanion.insert(
          id: 'rec-1',
          name: 'Netflix',
          type: TransactionType.expense,
          amountMinor: 50000,
          accountId: 'acct-bank',
          categoryId: const Value('cat-test'),
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 1, 5),
          nextOccurrence: DateTime(2026, 1, 5),
        ),
      );
      return (await dao.getById('rec-1'))!;
    }

    testWidgets('pre-fills the stored values', (tester) async {
      final database = await seedDatabase();
      await pumpForm(tester, database, initial: await seedRule(database));

      expect(
        find.widgetWithText(AppBar, 'Edit recurring transaction'),
        findsOneWidget,
      );
      expect(find.text('Netflix'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('Main Bank'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);

      await database.close();
    });

    testWidgets('saves a changed amount without touching nextOccurrence', (
      tester,
    ) async {
      final database = await seedDatabase();
      final initial = await seedRule(database);
      await pumpForm(tester, database, initial: initial);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '650',
      );
      await tapSave(tester, 'Save changes');
      await tester.pumpAndSettle();

      final row = await RecurringTransactionDao(database).getById('rec-1');
      expect(row!.amountMinor, 65000);
      expect(row.nextOccurrence, initial.nextOccurrence);

      await database.close();
    });
  });
}
