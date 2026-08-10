import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/loans/application/loan_controller.dart';
import 'package:finos_app/features/loans/data/loan_dao.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/loans/domain/loan_progress.dart';
import 'package:finos_app/features/loans/domain/loan_status.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loan lifecycle rules: outstanding, overpayment, standing, and deletion
/// (FR-06, docs/DATA_MODEL.md §32–§36, ADR-004).
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late TransactionDao transactions;
  late LoanDao loans;
  late LoanController controller;

  setUp(() async {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    transactions = TransactionDao(database);
    loans = LoanDao(database);
    controller = LoanController(database, loans, transactions, accounts);

    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
        openingBalanceMinor: const Value(10000000),
      ),
    );
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-closed',
        name: 'Closed Account',
        type: AccountType.bank,
        status: const Value(AccountStatus.archived),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<LoanProgress> progressOf(String loanId) async =>
      controller.progressFor((await loans.getById(loanId))!);

  group('create', () {
    test('stores the loan and returns its id', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        startDate: DateTime(2026, 8, 5, 14, 30),
        dueDate: DateTime(2026, 12, 1),
        description: 'Emergency help',
      );

      final loan = await loans.getById(id);
      expect(loan, isNotNull);
      expect(loan!.type, LoanDirection.lent);
      expect(loan.name, 'John');
      expect(loan.principalMinor, 2000000);
      expect(loan.status, LoanStatus.active);
      // Dates are normalised to calendar dates (docs/DATA_MODEL.md §42).
      expect(loan.startDate, DateTime(2026, 8, 5));
      expect(loan.dueDate, DateTime(2026, 12, 1));
      expect(loan.description, 'Emergency help');
    });

    test('trims the name', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: '  John  ',
        principalMinor: 2000000,
      );

      expect((await loans.getById(id))!.name, 'John');
    });

    test('rejects an empty name', () async {
      expect(
        () => controller.create(
          direction: LoanDirection.lent,
          name: '   ',
          principalMinor: 2000000,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a zero principal', () async {
      expect(
        () => controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a negative principal', () async {
      expect(
        () => controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: -100,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a due date before the start date', () async {
      expect(
        () => controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 2000000,
          startDate: DateTime(2026, 8, 10),
          dueDate: DateTime(2026, 8, 1),
        ),
        throwsArgumentError,
      );
    });

    test('accepts a due date equal to the start date', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        startDate: DateTime(2026, 8, 10),
        dueDate: DateTime(2026, 8, 10),
      );

      expect((await loans.getById(id))!.dueDate, DateTime(2026, 8, 10));
    });

    test('rejects a missing disbursement account', () async {
      expect(
        () => controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 2000000,
          disbursementAccountId: 'acct-ghost',
        ),
        throwsStateError,
      );
    });

    test('rejects an archived disbursement account', () async {
      expect(
        () => controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 2000000,
          disbursementAccountId: 'acct-closed',
        ),
        throwsStateError,
      );
    });

    test('a rejected creation leaves nothing behind', () async {
      // The loan and its origination movement are written in one transaction, so
      // a failure must not leave a half-created loan.
      await expectLater(
        () => controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 2000000,
          disbursementAccountId: 'acct-ghost',
        ),
        throwsStateError,
      );

      expect(await loans.getAll(), isEmpty);
      expect(await transactions.getAll(), isEmpty);
    });

    test(
      'writes a readable description onto the origination movement',
      () async {
        final lent = await controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 2000000,
          disbursementAccountId: 'acct-bank',
        );
        final borrowed = await controller.create(
          direction: LoanDirection.borrowed,
          name: 'Bank',
          principalMinor: 5000000,
          disbursementAccountId: 'acct-bank',
        );

        expect(
          (await transactions.forLoan(lent)).single.description,
          'Lent to John',
        );
        expect(
          (await transactions.forLoan(borrowed)).single.description,
          'Borrowed from Bank',
        );
      },
    );
  });

  group('outstanding', () {
    test('starts at the full principal', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );

      final progress = await progressOf(id);
      expect(progress.repaidMinor, 0);
      expect(progress.outstandingMinor, 2000000);
      expect(progress.repaidFraction, 0);
      expect(progress.isPaid, isFalse);
    });

    test('drops by each repayment', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );

      await controller.recordRepayment(
        loanId: id,
        amountMinor: 500000,
        accountId: 'acct-bank',
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 700000,
        accountId: 'acct-bank',
      );

      final progress = await progressOf(id);
      expect(progress.repaidMinor, 1200000);
      expect(progress.outstandingMinor, 800000);
      expect(progress.repaymentCount, 2);
      expect(progress.repaidFraction, closeTo(0.6, 0.0001));
    });

    test('does not count the origination movement as a repayment', () async {
      // Origination and repayment sit on opposite sides, so the origination
      // amount must never be mistaken for money repaid (ADR-004).
      final id = await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank',
        principalMinor: 5000000,
        disbursementAccountId: 'acct-bank',
      );

      final progress = await progressOf(id);
      expect(progress.repaidMinor, 0);
      expect(progress.outstandingMinor, 5000000);
    });

    test('reaches zero on full repayment', () async {
      final id = await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Bank',
        principalMinor: 5000000,
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 5000000,
        accountId: 'acct-bank',
      );

      final progress = await progressOf(id);
      expect(progress.outstandingMinor, 0);
      expect(progress.isPaid, isTrue);
      expect(progress.repaidFraction, 1);
      expect(progress.standing(), LoanStanding.paid);
    });
  });

  group('overpayment', () {
    test('rejects a repayment larger than the outstanding amount', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );

      expect(
        () => controller.recordRepayment(
          loanId: id,
          amountMinor: 2000001,
          accountId: 'acct-bank',
        ),
        throwsArgumentError,
      );
    });

    test(
      'accepts a repayment exactly equal to the outstanding amount',
      () async {
        final id = await controller.create(
          direction: LoanDirection.lent,
          name: 'John',
          principalMinor: 2000000,
        );

        await controller.recordRepayment(
          loanId: id,
          amountMinor: 2000000,
          accountId: 'acct-bank',
        );

        expect((await progressOf(id)).isPaid, isTrue);
      },
    );

    test('accounts for earlier repayments when checking the limit', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 1500000,
        accountId: 'acct-bank',
      );

      // Only ৳5,000 remains, so ৳6,000 must be refused.
      expect(
        () => controller.recordRepayment(
          loanId: id,
          amountMinor: 600000,
          accountId: 'acct-bank',
        ),
        throwsArgumentError,
      );
    });

    test('a rejected repayment records nothing', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );

      await expectLater(
        () => controller.recordRepayment(
          loanId: id,
          amountMinor: 9999999,
          accountId: 'acct-bank',
        ),
        throwsArgumentError,
      );

      expect(await transactions.getAll(), isEmpty);
      expect((await progressOf(id)).outstandingMinor, 2000000);
    });

    test('refuses further repayments once fully repaid', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 2000000,
        accountId: 'acct-bank',
      );

      expect(
        () => controller.recordRepayment(
          loanId: id,
          amountMinor: 1,
          accountId: 'acct-bank',
        ),
        throwsArgumentError,
      );
    });

    test('rejects a zero or negative repayment', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );

      expect(
        () => controller.recordRepayment(
          loanId: id,
          amountMinor: 0,
          accountId: 'acct-bank',
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.recordRepayment(
          loanId: id,
          amountMinor: -500,
          accountId: 'acct-bank',
        ),
        throwsArgumentError,
      );
    });

    test('rejects a repayment through an archived account', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );

      expect(
        () => controller.recordRepayment(
          loanId: id,
          amountMinor: 100000,
          accountId: 'acct-closed',
        ),
        throwsStateError,
      );
    });

    test('rejects a repayment for an unknown loan', () async {
      expect(
        () => controller.recordRepayment(
          loanId: 'loan-ghost',
          amountMinor: 100000,
          accountId: 'acct-bank',
        ),
        throwsStateError,
      );
    });

    test('rejects a repayment on an archived loan', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );
      await controller.archive(id);

      expect(
        () => controller.recordRepayment(
          loanId: id,
          amountMinor: 100000,
          accountId: 'acct-bank',
        ),
        throwsStateError,
      );
    });
  });

  group('standing', () {
    test('is outstanding when there is no due date', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );

      final progress = await progressOf(id);
      expect(progress.isOverdue(now: DateTime(2030)), isFalse);
      expect(progress.standing(now: DateTime(2030)), LoanStanding.outstanding);
    });

    test('is overdue once the due date has passed', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        startDate: DateTime(2026, 8, 1),
        dueDate: DateTime(2026, 9, 1),
      );

      final progress = await progressOf(id);
      expect(
        progress.standing(now: DateTime(2026, 9, 2)),
        LoanStanding.overdue,
      );
    });

    test('is not overdue on the due date itself', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        startDate: DateTime(2026, 8, 1),
        dueDate: DateTime(2026, 9, 1),
      );

      final progress = await progressOf(id);
      // The user still has the whole due day to pay.
      expect(
        progress.standing(now: DateTime(2026, 9, 1, 23, 59)),
        LoanStanding.outstanding,
      );
    });

    test('a fully repaid loan is never overdue', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        startDate: DateTime(2026, 8, 1),
        dueDate: DateTime(2026, 9, 1),
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 2000000,
        accountId: 'acct-bank',
        date: DateTime(2026, 8, 15),
      );

      final progress = await progressOf(id);
      expect(progress.isOverdue(now: DateTime(2027)), isFalse);
      expect(progress.standing(now: DateTime(2027)), LoanStanding.paid);
    });
  });

  group('update', () {
    test('changes the name, due date, and note', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        startDate: DateTime(2026, 8, 1),
      );

      await controller.update(
        id: id,
        name: 'John Smith',
        dueDate: DateTime(2026, 10, 1),
        description: 'Updated note',
      );

      final loan = await loans.getById(id);
      expect(loan!.name, 'John Smith');
      expect(loan.dueDate, DateTime(2026, 10, 1));
      expect(loan.description, 'Updated note');
      // Fixed at creation.
      expect(loan.principalMinor, 2000000);
      expect(loan.type, LoanDirection.lent);
    });

    test('can clear the due date', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        dueDate: DateTime(2026, 10, 1),
      );

      await controller.update(id: id, name: 'John');

      expect((await loans.getById(id))!.dueDate, isNull);
    });

    test('rejects a due date before the start date', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        startDate: DateTime(2026, 8, 10),
      );

      expect(
        () => controller.update(
          id: id,
          name: 'John',
          dueDate: DateTime(2026, 8, 1),
        ),
        throwsArgumentError,
      );
    });

    test('throws for an unknown loan', () async {
      expect(
        () => controller.update(id: 'loan-ghost', name: 'John'),
        throwsStateError,
      );
    });
  });

  group('lifecycle', () {
    test('archive then restore', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
      );

      await controller.archive(id);
      expect((await loans.getById(id))!.status, LoanStatus.archived);

      await controller.restore(id);
      expect((await loans.getById(id))!.status, LoanStatus.active);
    });

    test('deleting a loan removes its origination movement too', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
      );
      expect(await transactions.getAll(), hasLength(1));

      await controller.delete(id);

      expect(await loans.getById(id), isNull);
      expect(await transactions.getAll(), isEmpty);
      // The account is back to its opening balance.
      expect(await transactions.balanceImpactFor('acct-bank'), 0);
    });

    test('refuses to delete a loan that has repayments', () async {
      final id = await controller.create(
        direction: LoanDirection.lent,
        name: 'John',
        principalMinor: 2000000,
        disbursementAccountId: 'acct-bank',
      );
      await controller.recordRepayment(
        loanId: id,
        amountMinor: 500000,
        accountId: 'acct-bank',
      );

      // Repayments are financial history; archiving is the way to retire a loan
      // (docs/DATA_MODEL.md §47).
      await expectLater(
        () => controller.delete(id),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('Archive it instead'),
          ),
        ),
      );

      expect(await loans.getById(id), isNotNull);
      expect(await transactions.getAll(), hasLength(2));
    });

    test('deletes a loan with no movements at all', () async {
      final id = await controller.create(
        direction: LoanDirection.borrowed,
        name: 'Old Loan',
        principalMinor: 2000000,
      );

      await controller.delete(id);

      expect(await loans.getById(id), isNull);
    });

    test('delete throws for an unknown loan', () async {
      expect(() => controller.delete('loan-ghost'), throwsStateError);
    });
  });
}
