import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/errors/app_exception.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/backup/application/backup_service.dart';
import 'package:finos_app/features/backup/domain/backup_envelope.dart';
import 'package:finos_app/features/loans/application/loan_controller.dart';
import 'package:finos_app/features/loans/data/loan_dao.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loans in a backup (FR-08, docs/DATA_MODEL.md §48).
///
/// A backup that dropped loans would silently lose receivables and liabilities
/// while appearing to succeed, so the round trip is checked end to end.
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late TransactionDao transactions;
  late LoanDao loans;
  late LoanController controller;
  late BackupService service;

  setUp(() async {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    transactions = TransactionDao(database);
    loans = LoanDao(database);
    controller = LoanController(database, loans, transactions, accounts);
    service = BackupService(database);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(10000000),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  /// One loan of each direction, one with a disbursement and a repayment.
  Future<String> seedLoans() async {
    final lent = await controller.create(
      direction: LoanDirection.lent,
      name: 'John',
      principalMinor: 2000000,
      disbursementAccountId: 'acct-bank',
      startDate: DateTime(2026, 8, 1),
      dueDate: DateTime(2026, 12, 1),
      description: 'Emergency help',
    );
    await controller.recordRepayment(
      loanId: lent,
      amountMinor: 500000,
      accountId: 'acct-bank',
      date: DateTime(2026, 8, 20),
    );
    await controller.create(
      direction: LoanDirection.borrowed,
      name: 'Old Bank Loan',
      principalMinor: 25000000,
      startDate: DateTime(2025, 1, 15),
    );
    return lent;
  }

  group('export', () {
    test('includes a loans section', () async {
      final json = jsonDecode(await service.export()) as Map<String, Object?>;

      expect(json.containsKey(BackupFormat.loansKey), isTrue);
      expect(json[BackupFormat.loansKey], isA<List<Object?>>());
    });

    test('writes every loan field', () async {
      await seedLoans();
      final json = jsonDecode(await service.export()) as Map<String, Object?>;

      final entries = (json[BackupFormat.loansKey] as List)
          .cast<Map<String, Object?>>();
      expect(entries, hasLength(2));

      final lent = entries.firstWhere((row) => row['name'] == 'John');
      expect(lent['type'], 'LENT');
      expect(lent['principal_minor'], 2000000);
      expect(lent['currency'], 'BDT');
      expect(lent['disbursement_account_id'], 'acct-bank');
      expect(lent['status'], 'ACTIVE');
      expect(lent['description'], 'Emergency help');
      expect(lent['due_date'], '2026-12-01T00:00:00.000');

      final borrowed = entries.firstWhere(
        (row) => row['name'] == 'Old Bank Loan',
      );
      // A loan that pre-dates FinOS has no disbursement account or due date.
      expect(borrowed['disbursement_account_id'], isNull);
      expect(borrowed['due_date'], isNull);
    });

    test('links loan movements to their loan', () async {
      final lentId = await seedLoans();
      final json = jsonDecode(await service.export()) as Map<String, Object?>;

      final movements = (json[BackupFormat.transactionsKey] as List)
          .cast<Map<String, Object?>>();
      expect(movements, hasLength(2)); // origination plus one repayment
      for (final movement in movements) {
        expect(movement['loan_id'], lentId);
        expect(movement['category_id'], isNull);
      }
      expect(movements.map((m) => m['type']).toSet(), {
        'LOAN_PAYMENT',
        'LOAN_RECEIPT',
      });
    });

    test('an ordinary transaction carries a null loan_id', () async {
      await transactions.insertOne(
        TransactionsCompanion.insert(
          id: 'tx-food',
          type: TransactionType.expense,
          amountMinor: 150000,
          accountId: 'acct-bank',
          date: DateTime(2026, 8, 3),
        ),
      );

      final json = jsonDecode(await service.export()) as Map<String, Object?>;
      final movement = (json[BackupFormat.transactionsKey] as List)
          .cast<Map<String, Object?>>()
          .single;
      expect(movement['loan_id'], isNull);
    });
  });

  group('round trip', () {
    test(
      'restores loans, their movements, and the derived outstanding',
      () async {
        final lentId = await seedLoans();
        final before = await controller.progressFor(
          (await loans.getById(lentId))!,
        );
        final document = await service.export();

        // Clear everything, then restore.
        await service.restore(
          const ParsedBackup(
            accounts: [],
            categories: [],
            transactions: [],
            budgets: [],
            loans: [],
          ),
        );
        expect(await loans.getAll(), isEmpty);

        final counts = await service.importBackup(document);
        expect(counts.loans, 2);

        final restored = await loans.getById(lentId);
        expect(restored, isNotNull);
        expect(restored!.name, 'John');
        expect(restored.principalMinor, 2000000);
        expect(restored.dueDate, DateTime(2026, 12, 1));
        expect(restored.disbursementAccountId, 'acct-bank');

        // Outstanding is derived, so it comes back only if the movements did.
        final after = await controller.progressFor(restored);
        expect(after.repaidMinor, before.repaidMinor);
        expect(after.outstandingMinor, before.outstandingMinor);
        expect(after.outstandingMinor, 1500000);
      },
    );

    test('restores the balance effect of loan movements', () async {
      await seedLoans();
      final document = await service.export();
      final impactBefore = await transactions.balanceImpactFor('acct-bank');

      await service.importBackup(document);

      expect(await transactions.balanceImpactFor('acct-bank'), impactBefore);
      // −৳20,000 lent, +৳5,000 repaid.
      expect(impactBefore, -1500000);
    });

    test('counts loans in the totals shown before a restore', () async {
      await seedLoans();

      final counts = await service.currentCounts();
      expect(counts.loans, 2);
      expect(
        counts.total,
        counts.accounts +
            counts.categories +
            counts.transactions +
            counts.budgets +
            counts.loans,
      );
    });
  });

  group('validation', () {
    /// A document with a loan movement but no matching loan.
    String orphanedMovement() => jsonEncode({
      BackupFormat.versionKey: BackupFormat.version,
      BackupFormat.accountsKey: [
        {
          'id': 'acct-1',
          'name': 'Bank',
          'type': 'BANK',
          'currency': 'BDT',
          'opening_balance_minor': 0,
          'status': 'ACTIVE',
          'created_at': '2026-08-01T00:00:00.000',
          'updated_at': '2026-08-01T00:00:00.000',
        },
      ],
      BackupFormat.transactionsKey: [
        {
          'id': 'tx-orphan',
          'type': 'LOAN_PAYMENT',
          'amount_minor': 1000,
          'currency': 'BDT',
          'account_id': 'acct-1',
          'destination_account_id': null,
          'category_id': null,
          'loan_id': 'loan-ghost',
          'date': '2026-08-03T00:00:00.000',
          'description': '',
          'created_at': '2026-08-03T00:00:00.000',
          'updated_at': '2026-08-03T00:00:00.000',
        },
      ],
    });

    test('rejects a movement whose loan is missing', () async {
      expect(
        () => service.parse(orphanedMovement()),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('loan-ghost'),
          ),
        ),
      );
    });

    test('rejects a loan whose disbursement account is missing', () async {
      final contents = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.loansKey: [
          {
            'id': 'loan-1',
            'type': 'LENT',
            'name': 'John',
            'principal_minor': 2000000,
            'currency': 'BDT',
            'start_date': '2026-08-01T00:00:00.000',
            'due_date': null,
            'description': '',
            'disbursement_account_id': 'acct-ghost',
            'status': 'ACTIVE',
            'created_at': '2026-08-01T00:00:00.000',
            'updated_at': '2026-08-01T00:00:00.000',
          },
        ],
      });

      expect(
        () => service.parse(contents),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('acct-ghost'),
          ),
        ),
      );
    });

    test('rejects a non-positive principal', () async {
      final contents = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.loansKey: [
          {
            'id': 'loan-1',
            'type': 'LENT',
            'name': 'John',
            'principal_minor': 0,
            'currency': 'BDT',
            'start_date': '2026-08-01T00:00:00.000',
            'due_date': null,
            'description': '',
            'disbursement_account_id': null,
            'status': 'ACTIVE',
            'created_at': '2026-08-01T00:00:00.000',
            'updated_at': '2026-08-01T00:00:00.000',
          },
        ],
      });

      expect(
        () => service.parse(contents),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('greater than zero'),
          ),
        ),
      );
    });

    test('rejects an unrecognised loan direction', () async {
      final contents = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.loansKey: [
          {
            'id': 'loan-1',
            'type': 'GIFTED',
            'name': 'John',
            'principal_minor': 2000000,
            'currency': 'BDT',
            'start_date': '2026-08-01T00:00:00.000',
            'due_date': null,
            'description': '',
            'disbursement_account_id': null,
            'status': 'ACTIVE',
            'created_at': '2026-08-01T00:00:00.000',
            'updated_at': '2026-08-01T00:00:00.000',
          },
        ],
      });

      expect(
        () => service.parse(contents),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('unrecognised type'),
          ),
        ),
      );
    });

    test('a backup with no loans section still restores', () async {
      // Backups written before loans existed simply have nothing for them.
      final contents = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.accountsKey: <Object?>[],
        BackupFormat.categoriesKey: <Object?>[],
        BackupFormat.transactionsKey: <Object?>[],
        BackupFormat.budgetsKey: <Object?>[],
      });

      final parsed = service.parse(contents);
      expect(parsed.loans, isEmpty);

      final counts = await service.restore(parsed);
      expect(counts.loans, 0);
    });
  });
}
