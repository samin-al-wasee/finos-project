import 'dart:convert';

import 'package:finos_app/app/providers.dart';
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/errors/app_exception.dart';
import 'package:finos_app/core/theme/app_theme.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/backup/application/backup_service.dart';
import 'package:finos_app/features/backup/data/backup_file_store.dart';
import 'package:finos_app/features/backup/domain/backup_envelope.dart';
import 'package:finos_app/features/settings/presentation/settings_screen.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the export/import rows in Settings (FR-08).
///
/// The file store is faked: plugin method channels are unavailable under
/// `flutter test`, and the point here is the flow around the file — the
/// confirmation, the messages, and what reaches the database — not the share
/// sheet itself.
void main() {
  late _FakeFileStore store;

  setUp(() {
    store = _FakeFileStore();
  });

  Future<void> pumpSettings(WidgetTester tester, AppDatabase database) async {
    // A tall viewport keeps every settings row built and hit-testable.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          backupFileStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Seeds one account and one transaction so there is something to lose.
  Future<void> seedData(AppDatabase database) async {
    await AccountDao(database).insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-1',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await TransactionDao(database).insertOne(
      TransactionsCompanion.insert(
        id: 'tx-1',
        type: TransactionType.expense,
        amountMinor: 150000,
        accountId: 'acct-1',
        date: DateTime(2026, 8, 3),
      ),
    );
  }

  group('export', () {
    testWidgets('shows both data rows', (tester) async {
      final database = AppDatabase.inMemory();
      await pumpSettings(tester, database);

      expect(find.text('Export backup'), findsOneWidget);
      expect(find.text('Import backup'), findsOneWidget);

      await database.close();
    });

    testWidgets('hands a complete backup to the file store', (tester) async {
      final database = AppDatabase.inMemory();
      await seedData(database);
      await pumpSettings(tester, database);

      await tester.tap(find.text('Export backup'));
      await tester.pumpAndSettle();

      expect(store.exported, isNotNull);
      final json = jsonDecode(store.exported!) as Map<String, Object?>;
      expect(json[BackupFormat.versionKey], BackupFormat.version);
      expect(json[BackupFormat.accountsKey], hasLength(1));
      expect(json[BackupFormat.transactionsKey], hasLength(1));

      expect(find.text('Backup exported'), findsOneWidget);

      await database.close();
    });

    testWidgets('suggests a dated json file name', (tester) async {
      final database = AppDatabase.inMemory();
      await pumpSettings(tester, database);

      await tester.tap(find.text('Export backup'));
      await tester.pumpAndSettle();

      expect(
        store.exportedName,
        matches(r'^finos-backup-\d{4}-\d{2}-\d{2}\.json$'),
      );

      await database.close();
    });

    testWidgets('stays quiet when the share sheet is dismissed', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      store.shareAccepted = false;
      await pumpSettings(tester, database);

      await tester.tap(find.text('Export backup'));
      await tester.pumpAndSettle();

      // Cancelling is a deliberate choice, not an error worth reporting.
      expect(find.text('Backup exported'), findsNothing);

      await database.close();
    });

    testWidgets('reports a share failure readably', (tester) async {
      final database = AppDatabase.inMemory();
      store.failExport = true;
      await pumpSettings(tester, database);

      await tester.tap(find.text('Export backup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be shared'), findsOneWidget);

      await database.close();
    });
  });

  group('csv export', () {
    testWidgets('shows the row', (tester) async {
      final database = AppDatabase.inMemory();
      await pumpSettings(tester, database);

      expect(find.text('Export transactions (CSV)'), findsOneWidget);

      await database.close();
    });

    testWidgets('hands transaction rows to the file store', (tester) async {
      final database = AppDatabase.inMemory();
      await seedData(database);
      await pumpSettings(tester, database);

      await tester.tap(find.text('Export transactions (CSV)'));
      await tester.pumpAndSettle();

      expect(store.exportedCsv, isNotNull);
      final lines = store.exportedCsv!.trim().split('\n');
      expect(
        lines.first,
        'Date,Type,Account,Destination Account,Category,'
        'Amount,Currency,Description',
      );
      expect(lines, hasLength(2));
      expect(lines[1], contains('Main Bank'));
      expect(lines[1], contains('Expense'));

      expect(find.text('Transactions exported'), findsOneWidget);

      await database.close();
    });

    testWidgets('suggests a dated csv file name', (tester) async {
      final database = AppDatabase.inMemory();
      await pumpSettings(tester, database);

      await tester.tap(find.text('Export transactions (CSV)'));
      await tester.pumpAndSettle();

      expect(
        store.exportedCsvName,
        matches(r'^finos-transactions-\d{4}-\d{2}-\d{2}\.csv$'),
      );

      await database.close();
    });

    testWidgets('reports a share failure readably', (tester) async {
      final database = AppDatabase.inMemory();
      store.failExport = true;
      await pumpSettings(tester, database);

      await tester.tap(find.text('Export transactions (CSV)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be shared'), findsOneWidget);

      await database.close();
    });
  });

  group('import', () {
    /// A valid backup containing one account and nothing else.
    String backupWithOneAccount() => jsonEncode({
      BackupFormat.versionKey: BackupFormat.version,
      BackupFormat.exportedAtKey: '2026-08-10T12:00:00.000',
      BackupFormat.accountsKey: [
        {
          'id': 'acct-restored',
          'name': 'Restored Bank',
          'type': 'BANK',
          'currency': 'BDT',
          'opening_balance_minor': 250000,
          'status': 'ACTIVE',
          'created_at': '2026-08-01T00:00:00.000',
          'updated_at': '2026-08-01T00:00:00.000',
        },
      ],
      BackupFormat.categoriesKey: <Object?>[],
      BackupFormat.transactionsKey: <Object?>[],
      BackupFormat.budgetsKey: <Object?>[],
    });

    testWidgets('asks for confirmation before replacing anything', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      await seedData(database);
      store.toImport = backupWithOneAccount();
      await pumpSettings(tester, database);

      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();

      expect(find.text('Replace all data?'), findsOneWidget);
      // The dialog states both sides of the trade in records.
      expect(
        find.textContaining('This backup contains 1 account'),
        findsOneWidget,
      );
      expect(find.textContaining('It will replace'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await database.close();
    });

    testWidgets('cancelling leaves the data alone', (tester) async {
      final database = AppDatabase.inMemory();
      await seedData(database);
      store.toImport = backupWithOneAccount();
      await pumpSettings(tester, database);

      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      final accounts = AccountDao(database);
      expect(await accounts.getById('acct-1'), isNotNull);
      expect(await accounts.getById('acct-restored'), isNull);

      await database.close();
    });

    testWidgets('confirming replaces the data and reports what landed', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      await seedData(database);
      store.toImport = backupWithOneAccount();
      await pumpSettings(tester, database);

      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
      await tester.pumpAndSettle();

      final accounts = AccountDao(database);
      expect(await accounts.getById('acct-restored'), isNotNull);
      expect(await accounts.getById('acct-1'), isNull);
      expect(await TransactionDao(database).getById('tx-1'), isNull);
      expect(find.textContaining('Restored 1 account'), findsOneWidget);

      await database.close();
    });

    testWidgets('a cancelled file picker does nothing', (tester) async {
      final database = AppDatabase.inMemory();
      await seedData(database);
      store.toImport = null; // Picker cancelled.
      await pumpSettings(tester, database);

      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();

      expect(find.text('Replace all data?'), findsNothing);
      expect(await AccountDao(database).getById('acct-1'), isNotNull);

      await database.close();
    });

    testWidgets('an invalid file is rejected without a confirmation', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      await seedData(database);
      store.toImport = 'this is not a backup';
      await pumpSettings(tester, database);

      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();

      // Validation happens before the prompt, so the user is never asked to
      // confirm a restore that could not have worked.
      expect(find.text('Replace all data?'), findsNothing);
      expect(find.textContaining("isn't valid JSON"), findsOneWidget);
      expect(await AccountDao(database).getById('acct-1'), isNotNull);

      await database.close();
    });

    testWidgets('a backup from a newer format version is refused', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      await seedData(database);
      store.toImport = jsonEncode({
        BackupFormat.versionKey: 99,
        BackupFormat.accountsKey: <Object?>[],
      });
      await pumpSettings(tester, database);

      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('format version 99'), findsOneWidget);
      expect(await AccountDao(database).getById('acct-1'), isNotNull);

      await database.close();
    });

    testWidgets('a broken reference is named in the message', (tester) async {
      final database = AppDatabase.inMemory();
      store.toImport = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.accountsKey: <Object?>[],
        BackupFormat.transactionsKey: [
          {
            'id': 'tx-orphan',
            'type': 'EXPENSE',
            'amount_minor': 1000,
            'currency': 'BDT',
            'account_id': 'acct-ghost',
            'destination_account_id': null,
            'category_id': null,
            'date': '2026-08-03T00:00:00.000',
            'description': '',
            'created_at': '2026-08-03T00:00:00.000',
            'updated_at': '2026-08-03T00:00:00.000',
          },
        ],
      });
      await pumpSettings(tester, database);

      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('acct-ghost'), findsOneWidget);

      await database.close();
    });
  });

  group('round trip through the UI', () {
    testWidgets('exporting then importing restores the same data', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      await seedData(database);
      await pumpSettings(tester, database);

      await tester.tap(find.text('Export backup'));
      await tester.pumpAndSettle();
      final exported = store.exported!;

      // Clear everything, then restore from the file that was just exported.
      await BackupService(database).restore(
        const ParsedBackup(
          accounts: [],
          categories: [],
          transactions: [],
          budgets: [],
        ),
      );
      expect(await AccountDao(database).getById('acct-1'), isNull);

      store.toImport = exported;
      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
      await tester.pumpAndSettle();

      expect(await AccountDao(database).getById('acct-1'), isNotNull);
      final restored = await TransactionDao(database).getById('tx-1');
      expect(restored, isNotNull);
      expect(restored!.amountMinor, 150000);
      expect(restored.date, DateTime(2026, 8, 3));

      await database.close();
    });
  });
}

/// A [BackupFileStore] that keeps the "file" in memory.
class _FakeFileStore implements BackupFileStore {
  /// The contents handed to the last export.
  String? exported;

  /// The file name suggested by the last export.
  String? exportedName;

  /// The contents handed to the last CSV export.
  String? exportedCsv;

  /// The file name suggested by the last CSV export.
  String? exportedCsvName;

  /// Contents the next import should return; `null` simulates a cancelled
  /// picker.
  String? toImport;

  /// Whether the share sheet reports that the user chose a destination.
  bool shareAccepted = true;

  /// When true, exporting throws as the real store would on a platform failure.
  bool failExport = false;

  @override
  Future<bool> exportBackup(String contents, String fileName) async {
    if (failExport) {
      throw const UnexpectedException(
        'The backup could not be shared. Please try again.',
      );
    }
    exported = contents;
    exportedName = fileName;
    return shareAccepted;
  }

  @override
  Future<bool> exportCsv(String contents, String fileName) async {
    if (failExport) {
      throw const UnexpectedException(
        'The transactions could not be shared. Please try again.',
      );
    }
    exportedCsv = contents;
    exportedCsvName = fileName;
    return shareAccepted;
  }

  @override
  Future<String?> pickBackup() async => toImport;
}
