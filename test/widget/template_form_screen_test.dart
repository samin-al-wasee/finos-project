import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/templates/data/template_dao.dart';
import 'package:finos_app/features/templates/presentation/template_form_screen.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trivial host screen that pushes [TemplateFormScreen] on the first frame.
///
/// Popping the form returns to this scaffold, so pumpAndSettle finishes cleanly.
class _FormHost extends StatefulWidget {
  const _FormHost({this.initial});

  final TransactionTemplateRow? initial;

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
          builder: (_) => TemplateFormScreen(initial: widget.initial),
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
    TransactionTemplateRow? initial,
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
    await tester.pumpAndSettle();
    return database;
  }

  testWidgets('requires a name', (tester) async {
    final database = await pumpForm(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add template'));
    await tester.pump();

    expect(find.text('Enter a name for this template'), findsOneWidget);

    await database.close();
  });

  testWidgets('creates a template with just a name', (tester) async {
    final database = await pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).first, 'Netflix');
    await tester.tap(find.widgetWithText(FilledButton, 'Add template'));
    await tester.pumpAndSettle();

    expect(find.byType(TemplateFormScreen), findsNothing);
    final rows = await TemplateDao(database).getAll();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Netflix');
    expect(rows.single.amountMinor, isNull);

    await database.close();
  });

  testWidgets('rejects a zero amount but allows a blank one', (tester) async {
    final database = await pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).first, 'Test');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (optional)'),
      '0',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add template'));
    await tester.pump();

    expect(find.text('Amount must be greater than zero'), findsOneWidget);

    await database.close();
  });

  testWidgets('creates a template with a preset amount and account', (
    tester,
  ) async {
    final database = await pumpForm(tester);
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Netflix');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (optional)'),
      '500',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Bank').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add template'));
    await tester.pumpAndSettle();

    final rows = await TemplateDao(database).getAll();
    expect(rows.single.amountMinor, 50000);
    expect(rows.single.accountId, 'acct-1');

    await database.close();
  });

  testWidgets('pre-fills values in edit mode', (tester) async {
    final database = await pumpForm(
      tester,
      initial: TransactionTemplateRow(
        id: 'tpl-1',
        name: 'Netflix',
        type: TransactionType.expense,
        amountMinor: 50000,
        description: 'Streaming',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );

    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('Streaming'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Edit template'), findsOneWidget);

    await database.close();
  });

  testWidgets('saves edits to an existing template', (tester) async {
    final database = AppDatabase.inMemory();
    await TemplateDao(database).insertOne(
      TransactionTemplatesCompanion.insert(
        id: 'tpl-1',
        name: 'Netflix',
        type: TransactionType.expense,
      ),
    );
    final existing = await TemplateDao(database).getById('tpl-1');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: _FormHost(initial: existing),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Netflix Plus');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    final updated = await TemplateDao(database).getById('tpl-1');
    expect(updated!.name, 'Netflix Plus');

    await database.close();
  });
}
