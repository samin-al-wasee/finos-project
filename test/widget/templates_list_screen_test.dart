import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/templates/data/template_dao.dart';
import 'package:finos_app/features/templates/presentation/template_form_screen.dart';
import 'package:finos_app/features/templates/presentation/templates_list_screen.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:finos_app/features/transactions/presentation/transaction_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppDatabase> pumpList(WidgetTester tester) async {
    final database = AppDatabase.inMemory();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TemplatesListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  testWidgets('shows an empty state when there are no templates', (
    tester,
  ) async {
    final database = await pumpList(tester);

    expect(find.text('No templates yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add template'), findsOneWidget);

    await database.close();
  });

  testWidgets('the FAB opens the template form', (tester) async {
    final database = await pumpList(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(TemplateFormScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'New template'), findsOneWidget);

    await database.close();
  });

  testWidgets('renders a saved template with its preview', (tester) async {
    final database = await pumpList(tester);
    await TemplateDao(database).insertOne(
      TransactionTemplatesCompanion.insert(
        id: 'tpl-1',
        name: 'Netflix',
        type: TransactionType.expense,
        amountMinor: const Value(50000),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Netflix'), findsOneWidget);
    expect(find.textContaining('Expense'), findsOneWidget);
    expect(find.textContaining('৳500.00'), findsOneWidget);

    await database.close();
  });

  testWidgets('tapping a template opens a pre-filled transaction form', (
    tester,
  ) async {
    final database = await pumpList(tester);
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await CategoryDao(database).insertOne(
      CategoriesCompanion.insert(
        id: 'cat-1',
        name: 'Entertainment',
        type: CategoryType.expense,
      ),
    );
    await TemplateDao(database).insertOne(
      TransactionTemplatesCompanion.insert(
        id: 'tpl-1',
        name: 'Netflix',
        type: TransactionType.expense,
        amountMinor: const Value(50000),
        accountId: const Value('acct-1'),
        categoryId: const Value('cat-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Netflix'));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionFormScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Add transaction'), findsOneWidget);
    // The amount is pre-filled from the template.
    expect(find.text('500'), findsOneWidget);

    await database.close();
  });

  testWidgets('the menu edit item opens the form for that template', (
    tester,
  ) async {
    final database = await pumpList(tester);
    await TemplateDao(database).insertOne(
      TransactionTemplatesCompanion.insert(
        id: 'tpl-1',
        name: 'Netflix',
        type: TransactionType.expense,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(TemplateFormScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Edit template'), findsOneWidget);

    await database.close();
  });

  testWidgets('delete requires confirmation and removes the template', (
    tester,
  ) async {
    final database = await pumpList(tester);
    await TemplateDao(database).insertOne(
      TransactionTemplatesCompanion.insert(
        id: 'tpl-1',
        name: 'Netflix',
        type: TransactionType.expense,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this template?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await TemplateDao(database).getById('tpl-1'), isNotNull);
    expect(find.text('Netflix'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(await TemplateDao(database).getById('tpl-1'), isNull);
    expect(find.text('No templates yet'), findsOneWidget);

    await database.close();
  });
}
