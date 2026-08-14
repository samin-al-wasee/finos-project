import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/investments/application/investment_controller.dart';
import 'package:finos_app/features/investments/data/investment_dao.dart';
import 'package:finos_app/features/investments/domain/investment_contribution_mode.dart';
import 'package:finos_app/features/investments/domain/investment_instrument_type.dart';
import 'package:finos_app/features/investments/presentation/investment_details_screen.dart';
import 'package:finos_app/features/investments/presentation/investment_form_screen.dart';
import 'package:finos_app/features/investments/presentation/investments_list_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the Investments screen and its detail screen
/// (docs/adr/009-investment-accounting.md).
void main() {
  /// Creates a database with one active account to move investment money
  /// through.
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

  InvestmentController controllerFor(AppDatabase database) =>
      InvestmentController(
        database,
        InvestmentDao(database),
        TransactionDao(database),
        AccountDao(database),
      );

  Future<void> pumpInvestments(
    WidgetTester tester,
    AppDatabase database,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const InvestmentsListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('list', () {
    testWidgets('shows an empty state with no investments', (tester) async {
      final database = await seedDatabase();
      await pumpInvestments(tester, database);

      expect(find.text('No investments yet'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Add investment'),
        findsOneWidget,
      );

      await database.close();
    });

    testWidgets('the empty state opens the investment form', (tester) async {
      final database = await seedDatabase();
      await pumpInvestments(tester, database);

      await tester.tap(find.widgetWithText(FilledButton, 'Add investment'));
      await tester.pumpAndSettle();

      expect(find.byType(InvestmentFormScreen), findsOneWidget);

      await database.close();
    });

    testWidgets('lists a created investment with its contributed amount', (
      tester,
    ) async {
      final database = await seedDatabase();
      await controllerFor(database).create(
        name: '1-year FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime.now().add(const Duration(days: 365)),
      );
      await pumpInvestments(tester, database);

      expect(find.text('1-year FDR'), findsOneWidget);
      expect(find.textContaining('৳20,000'), findsWidgets);

      await database.close();
    });
  });

  group('create', () {
    testWidgets('creates a lump-sum investment and moves the money', (
      tester,
    ) async {
      final database = await seedDatabase();
      await pumpInvestments(tester, database);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '1-year FDR');
      await tester.enterText(find.byType(TextFormField).at(1), '20000');

      // Source account — the only account, so it's the only option.
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Bank').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add investment'));
      await tester.pumpAndSettle();

      final investments = await InvestmentDao(database).getAll();
      expect(investments, hasLength(1));
      expect(investments.single.name, '1-year FDR');
      expect(investments.single.amountMinor, 2000000);
      expect(
        await TransactionDao(database).balanceImpactFor('acct-bank'),
        -2000000,
      );

      await database.close();
    });

    testWidgets('requires a name', (tester) async {
      final database = await seedDatabase();
      await pumpInvestments(tester, database);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), '20000');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Bank').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add investment'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a name for this investment'), findsOneWidget);
      expect(await InvestmentDao(database).getAll(), isEmpty);

      await database.close();
    });

    testWidgets('requires a positive amount', (tester) async {
      final database = await seedDatabase();
      await pumpInvestments(tester, database);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '1-year FDR');
      await tester.enterText(find.byType(TextFormField).at(1), '0');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Bank').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add investment'));
      await tester.pumpAndSettle();

      expect(find.text('Amount must be greater than zero'), findsOneWidget);
      expect(await InvestmentDao(database).getAll(), isEmpty);

      await database.close();
    });
  });

  group('details', () {
    Future<void> pumpDetails(
      WidgetTester tester,
      AppDatabase database,
      String investmentId,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: InvestmentDetailsScreen(investmentId: investmentId),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows contributed and paid-out figures', (tester) async {
      final database = await seedDatabase();
      final id = await controllerFor(database).create(
        name: '1-year FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime.now().add(const Duration(days: 365)),
      );
      await pumpDetails(tester, database, id);

      expect(find.text('Contributed'), findsOneWidget);
      expect(find.textContaining('৳20,000'), findsWidgets);
      expect(find.text('Active'), findsOneWidget);

      await database.close();
    });

    testWidgets(
      'confirming a maturity payout records it and settles the investment',
      (tester) async {
        final database = await seedDatabase();
        final id = await controllerFor(database).create(
          name: '1-year FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 2000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          startDate: DateTime(2020, 1, 1),
          maturityDate: DateTime(2020, 6, 1), // long past — already matured
        );
        await pumpDetails(tester, database, id);

        expect(find.text('Maturity payout due'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
        await tester.pumpAndSettle();

        // Two "Confirm" buttons are now on screen: the due-payout card
        // behind the dialog, and the dialog's own action — the dialog's is
        // the one built last.
        await tester.enterText(find.byType(TextFormField).first, '22000');
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm').last);
        await tester.pumpAndSettle();

        expect(find.text('Settled'), findsOneWidget);
        final progress = await controllerFor(
          database,
        ).progressFor((await InvestmentDao(database).getById(id))!);
        expect(progress.payoutReceivedMinor, 2200000);

        await database.close();
      },
    );

    testWidgets('refuses to delete once a payout is recorded, but archive '
        'works', (tester) async {
      final database = await seedDatabase();
      final controller = controllerFor(database);
      final id = await controller.create(
        name: '1-year FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        maturityDate: DateTime.now().add(const Duration(days: 365)),
      );
      await controller.confirmNextPayout(id, amountMinor: 100000);
      await pumpDetails(tester, database, id);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Archive it instead'), findsOneWidget);
      expect(await InvestmentDao(database).getById(id), isNotNull);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      expect(find.text('Archived'), findsOneWidget);

      await database.close();
    });

    testWidgets(
      'withdrawing part of the principal shows the remaining amount',
      (tester) async {
        final database = await seedDatabase();
        final id = await controllerFor(database).create(
          name: '1-year FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 2000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime.now().add(const Duration(days: 365)),
        );
        await pumpDetails(tester, database, id);

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Withdraw'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, '5000');
        await tester.tap(find.widgetWithText(FilledButton, 'Withdraw').last);
        await tester.pumpAndSettle();

        expect(find.text('Withdrawal recorded'), findsOneWidget);
        expect(find.text('Withdrawn early'), findsOneWidget);
        expect(find.text('Remaining principal'), findsOneWidget);
        expect(find.textContaining('৳15,000'), findsWidgets);
        expect(find.text('Active'), findsOneWidget);

        await database.close();
      },
    );

    testWidgets(
      'withdrawing the full principal shows Fully withdrawn without '
      'archiving',
      (tester) async {
        final database = await seedDatabase();
        final id = await controllerFor(database).create(
          name: '1-year FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 2000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime.now().add(const Duration(days: 365)),
        );
        await pumpDetails(tester, database, id);

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Withdraw'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, '20000');
        await tester.tap(find.widgetWithText(FilledButton, 'Withdraw').last);
        await tester.pumpAndSettle();

        expect(find.text('Fully withdrawn'), findsOneWidget);

        final progress = await controllerFor(
          database,
        ).progressFor((await InvestmentDao(database).getById(id))!);
        expect(progress.isFullyWithdrawn, isTrue);
        expect(progress.isArchived, isFalse);
        // No more Withdraw action once nothing remains.
        expect(find.text('Withdraw'), findsNothing);

        await database.close();
      },
    );

    testWidgets(
      'rejects a withdrawal amount larger than what remains',
      (tester) async {
        final database = await seedDatabase();
        final id = await controllerFor(database).create(
          name: '1-year FDR',
          instrumentType: InvestmentInstrumentType.fdr,
          contributionMode: InvestmentContributionMode.lumpSum,
          amountMinor: 2000000,
          sourceAccountId: 'acct-bank',
          payoutAccountId: 'acct-bank',
          maturityDate: DateTime.now().add(const Duration(days: 365)),
        );
        await pumpDetails(tester, database, id);

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Withdraw'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, '99999');
        await tester.tap(find.widgetWithText(FilledButton, 'Withdraw').last);
        await tester.pumpAndSettle();

        expect(find.text('That is more than what remains'), findsOneWidget);

        await database.close();
      },
    );

    testWidgets('no Withdraw action once the investment has matured', (
      tester,
    ) async {
      final database = await seedDatabase();
      final id = await controllerFor(database).create(
        name: '1-year FDR',
        instrumentType: InvestmentInstrumentType.fdr,
        contributionMode: InvestmentContributionMode.lumpSum,
        amountMinor: 2000000,
        sourceAccountId: 'acct-bank',
        payoutAccountId: 'acct-bank',
        startDate: DateTime(2020, 1, 1),
        maturityDate: DateTime(2020, 6, 1), // long past — already matured
      );
      await pumpDetails(tester, database, id);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Withdraw'), findsNothing);

      await database.close();
    });
  });
}
