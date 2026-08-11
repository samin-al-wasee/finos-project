import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_origin.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/categories/presentation/category_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trivial host screen that pushes [CategoryFormScreen] on the first frame.
///
/// Popping the form returns to this scaffold, so pumpAndSettle finishes cleanly.
class _FormHost extends StatefulWidget {
  const _FormHost({this.initial});

  final CategoryRow? initial;

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
          builder: (_) => CategoryFormScreen(initial: widget.initial),
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
    CategoryRow? initial,
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

  testWidgets('requires a category name', (tester) async {
    final database = await pumpForm(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add category'));
    await tester.pump();

    expect(find.text('Enter a category name'), findsOneWidget);

    await database.close();
  });

  testWidgets('rejects names longer than 40 characters', (tester) async {
    final database = await pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'a' * 41);
    await tester.tap(find.widgetWithText(FilledButton, 'Add category'));
    await tester.pump();

    expect(find.text('Name must be 40 characters or fewer'), findsOneWidget);

    await database.close();
  });

  testWidgets('creates a category and persists it', (tester) async {
    final database = await pumpForm(tester);
    final dao = CategoryDao(database);

    await tester.enterText(find.byType(TextFormField).at(0), 'Groceries');

    // Type is chosen at creation; the icon picker marks a selection.
    await tester.tap(find.byType(DropdownButtonFormField<CategoryType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('icon-shopping_bag')));

    await tester.tap(find.widgetWithText(FilledButton, 'Add category'));
    await tester.pumpAndSettle();

    // Form should have popped back to the host.
    expect(find.byType(CategoryFormScreen), findsNothing);

    final userRows = (await dao.getAll())
        .where((r) => r.origin == CategoryOrigin.user)
        .toList();
    expect(userRows, hasLength(1));
    final row = userRows.single;
    expect(row.name, 'Groceries');
    expect(row.type, CategoryType.income);
    expect(row.icon, 'shopping_bag');
    expect(row.origin, CategoryOrigin.user);
    expect(row.status, CategoryStatus.active);

    await database.close();
  });

  testWidgets('pre-fills values in edit mode', (tester) async {
    final database = AppDatabase.inMemory();
    final dao = CategoryDao(database);
    await dao.insertOne(
      CategoriesCompanion.insert(
        id: 'c1',
        name: 'Groceries',
        type: CategoryType.expense,
        icon: const Value('shopping_bag'),
      ),
    );
    final row = (await dao.getById('c1'))!;

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

    expect(find.widgetWithText(AppBar, 'Edit category'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);

    // A category's type is fixed at creation, so the picker is hidden.
    expect(find.byType(DropdownButtonFormField<CategoryType>), findsNothing);

    await database.close();
  });

  testWidgets('saves edits to an existing category', (tester) async {
    final database = AppDatabase.inMemory();
    final dao = CategoryDao(database);
    await dao.insertOne(
      CategoriesCompanion.insert(
        id: 'c1',
        name: 'Groceries',
        type: CategoryType.expense,
      ),
    );
    final row = (await dao.getById('c1'))!;

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

    await tester.enterText(find.byType(TextFormField).at(0), 'Fresh Market');
    await tester.tap(find.byKey(const ValueKey('icon-restaurant')));
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryFormScreen), findsNothing);

    final updated = await dao.getById('c1');
    expect(updated!.name, 'Fresh Market');
    expect(updated.icon, 'restaurant');

    await database.close();
  });

  testWidgets('the icon picker has accessible, adequately sized tap targets '
      '(docs/UI_DESIGN.md §43-44)', (tester) async {
    final handle = tester.ensureSemantics();
    final database = await pumpForm(tester);

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    handle.dispose();
    await database.close();
  });
}
