import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../../accounts/data/account_dao.dart';
import '../../accounts/domain/account_status.dart';
import '../../transactions/data/transaction_dao.dart';
import '../data/loan_dao.dart';
import '../domain/loan_direction.dart';
import '../domain/loan_progress.dart';
import '../domain/loan_status.dart';

/// Application-service for the loan lifecycle (FR-06, ADR-004).
///
/// Owns the rules that keep a loan and the money behind it in step:
///
/// * creating a loan with a disbursement account also records the cash movement,
///   atomically — a loan that moved money must never exist without its
///   transaction, and vice versa
/// * a repayment is a transaction carrying the loan's id, on the opposite side
///   from origination
/// * a repayment may not exceed what is still outstanding
///   (docs/DATA_MODEL.md §36)
class LoanController {
  LoanController(this._database, this._dao, this._transactions, this._accounts);

  final AppDatabase _database;
  final LoanDao _dao;
  final TransactionDao _transactions;
  final AccountDao _accounts;

  /// Creates a loan, and its origination transaction when
  /// [disbursementAccountId] is given.
  ///
  /// Leave [disbursementAccountId] null for a loan that pre-dates FinOS: it is
  /// opening state and moves no money today.
  ///
  /// Returns the generated loan id.
  Future<String> create({
    required LoanDirection direction,
    required String name,
    required int principalMinor,
    String? disbursementAccountId,
    DateTime? startDate,
    DateTime? dueDate,
    String description = '',
    String currency = 'BDT',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Enter who the loan is with');
    }
    if (principalMinor <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }

    final start = _dayStart(startDate ?? DateTime.now());
    final due = dueDate == null ? null : _dayStart(dueDate);
    if (due != null && due.isBefore(start)) {
      throw ArgumentError('The due date must be on or after the start date');
    }

    if (disbursementAccountId != null) {
      await _requireActiveAccount(disbursementAccountId);
    }

    final id = generateId();
    // One transaction so a loan can never be left without the movement that
    // created it, or the movement without its loan.
    await _database.transaction(() async {
      await _dao.insertOne(
        LoansCompanion.insert(
          id: id,
          type: direction,
          name: trimmedName,
          principalMinor: principalMinor,
          currency: Value(currency),
          startDate: start,
          dueDate: Value(due),
          description: Value(description),
          disbursementAccountId: Value(disbursementAccountId),
        ),
      );

      if (disbursementAccountId != null) {
        await _transactions.insertOne(
          TransactionsCompanion.insert(
            id: generateId(),
            type: originationTypeFor(direction),
            amountMinor: principalMinor,
            currency: Value(currency),
            accountId: disbursementAccountId,
            // Loan movements never carry a category, so they cannot reach
            // spending analytics or budgets (ADR-004).
            categoryId: const Value(null),
            loanId: Value(id),
            date: start,
            description: Value(_originationDescription(direction, trimmedName)),
          ),
        );
      }
    });

    return id;
  }

  /// Records a repayment against the loan identified by [loanId].
  ///
  /// The movement is a transaction on the opposite side from origination, so it
  /// both adjusts the account balance and reduces the outstanding amount.
  ///
  /// Throws [ArgumentError] if the amount is not positive or exceeds what is
  /// outstanding, and [StateError] if the loan or account does not exist.
  Future<String> recordRepayment({
    required String loanId,
    required int amountMinor,
    required String accountId,
    DateTime? date,
    String description = '',
  }) async {
    if (amountMinor <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }

    final loan = await _dao.getById(loanId);
    if (loan == null) throw StateError('Loan not found: $loanId');
    if (loan.status == LoanStatus.archived) {
      throw StateError('This loan is archived');
    }
    await _requireActiveAccount(accountId);

    final progress = await progressFor(loan);
    if (progress.isPaid) {
      throw ArgumentError('This loan is already fully repaid');
    }
    // Overpayment is rejected rather than silently clamped
    // (docs/DATA_MODEL.md §36).
    if (amountMinor > progress.outstandingMinor) {
      throw ArgumentError(
        'That is more than the ${_formatOutstanding(progress)} still '
        'outstanding',
      );
    }

    final id = generateId();
    await _transactions.insertOne(
      TransactionsCompanion.insert(
        id: id,
        type: repaymentTypeFor(loan.type),
        amountMinor: amountMinor,
        currency: Value(loan.currency),
        accountId: accountId,
        categoryId: const Value(null),
        loanId: Value(loanId),
        date: _dayStart(date ?? DateTime.now()),
        description: Value(
          description.isEmpty ? 'Repayment · ${loan.name}' : description,
        ),
      ),
    );
    return id;
  }

  /// Updates the editable fields of a loan.
  ///
  /// The direction, principal, and disbursement account are fixed at creation:
  /// changing any of them would leave the origination transaction and every
  /// derived figure describing a loan that no longer exists.
  Future<void> update({
    required String id,
    required String name,
    DateTime? dueDate,
    String description = '',
  }) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Loan not found: $id');

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Enter who the loan is with');
    }
    final due = dueDate == null ? null : _dayStart(dueDate);
    if (due != null && due.isBefore(row.startDate)) {
      throw ArgumentError('The due date must be on or after the start date');
    }

    await _dao.updateOne(
      row.copyWith(
        name: trimmedName,
        dueDate: Value(due),
        description: description,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Archives a loan, keeping it and its transactions for reference.
  Future<void> archive(String id) => _dao.updateStatus(id, LoanStatus.archived);

  /// Re-activates an archived loan.
  Future<void> restore(String id) => _dao.updateStatus(id, LoanStatus.active);

  /// Permanently deletes a loan that has no repayments.
  ///
  /// Any origination transaction goes with it, in one database transaction. A
  /// loan with repayments is refused: those are financial history, and archiving
  /// is the correct way to retire it (docs/DATA_MODEL.md §47).
  Future<void> delete(String id) async {
    final loan = await _dao.getById(id);
    if (loan == null) throw StateError('Loan not found: $id');

    final hasRepayments = await _transactions.hasLoanMovement(
      id,
      repaymentTypeFor(loan.type),
    );
    if (hasRepayments) {
      throw ArgumentError(
        'This loan has repayments recorded. Archive it instead of deleting it.',
      );
    }

    await _database.transaction(() async {
      await _transactions.deleteForLoan(id);
      await _dao.deleteOne(id);
    });
  }

  /// Returns the loan identified by [id], or `null` if not found.
  Future<LoanRow?> getById(String id) => _dao.getById(id);

  /// Derives everything about [loan] that depends on its repayments.
  Future<LoanProgress> progressFor(LoanRow loan) async {
    final repaymentType = repaymentTypeFor(loan.type);
    final repaidMinor = await _transactions.loanMovementTotal(
      loan.id,
      repaymentType,
    );
    final movements = await _transactions.forLoan(loan.id);
    return LoanProgress(
      loan: loan,
      repaidMinor: repaidMinor,
      repaymentCount: movements
          .where((row) => row.type == repaymentType)
          .length,
    );
  }

  Future<void> _requireActiveAccount(String accountId) async {
    final account = await _accounts.getById(accountId);
    if (account == null) throw StateError('Account not found: $accountId');
    if (account.status != AccountStatus.active) {
      throw StateError('Account is not active: ${account.name}');
    }
  }

  /// The description written onto an origination transaction.
  ///
  /// Written at creation so the transaction list reads correctly without having
  /// to resolve loan names. A later rename leaves this text as a historical
  /// record of what the loan was called at the time.
  static String _originationDescription(LoanDirection direction, String name) {
    switch (direction) {
      case LoanDirection.lent:
        return 'Lent to $name';
      case LoanDirection.borrowed:
        return 'Borrowed from $name';
    }
  }

  static String _formatOutstanding(LoanProgress progress) {
    // Minor units are formatted at the presentation boundary; the message only
    // needs the magnitude, so this stays currency-symbol free.
    final major = progress.outstandingMinor / 100;
    return major.toStringAsFixed(2);
  }

  static DateTime _dayStart(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
