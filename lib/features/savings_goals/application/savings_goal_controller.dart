import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../../accounts/data/account_dao.dart';
import '../../accounts/domain/account_status.dart';
import '../../transactions/data/transaction_dao.dart';
import '../../transactions/domain/transaction_type.dart';
import '../data/savings_goal_dao.dart';
import '../domain/savings_goal_progress.dart';
import '../domain/savings_goal_status.dart';

/// Application-service for the savings goal lifecycle
/// (docs/adr/011-savings-goals.md).
///
/// Owns the rules that keep a goal and the money behind it in step, the same
/// role [LoanController] plays for loans:
///
/// * creating a goal never moves money — every contribution and withdrawal
///   is a separate, on-demand action, exactly like a loan's repayments
/// * a contribution or withdrawal is a transaction carrying the goal's id,
///   on opposite sides of its single linked account
/// * a withdrawal may not exceed what is currently saved
///   (docs/adr/011-savings-goals.md §3); a contribution has no upper cap
class SavingsGoalController {
  SavingsGoalController(
    this._database,
    this._dao,
    this._transactions,
    this._accounts,
  );

  final AppDatabase _database;
  final SavingsGoalDao _dao;
  final TransactionDao _transactions;
  final AccountDao _accounts;

  /// Creates a savings goal. No transaction is recorded — every
  /// contribution is a separate, on-demand action (docs/adr/011-savings-goals.md
  /// §2).
  ///
  /// Returns the generated goal id.
  Future<String> create({
    required String name,
    required int targetAmountMinor,
    required String accountId,
    DateTime? startDate,
    DateTime? deadlineDate,
    String description = '',
    String currency = 'BDT',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Enter a name for this goal');
    }
    if (targetAmountMinor <= 0) {
      throw ArgumentError('Target amount must be greater than zero');
    }

    final start = _dayStart(startDate ?? DateTime.now());
    final deadline = deadlineDate == null ? null : _dayStart(deadlineDate);
    if (deadline != null && deadline.isBefore(start)) {
      throw ArgumentError('The deadline must be on or after the start date');
    }

    await _requireActiveAccount(accountId);

    final id = generateId();
    await _dao.insertOne(
      SavingsGoalsCompanion.insert(
        id: id,
        name: trimmedName,
        targetAmountMinor: targetAmountMinor,
        currency: Value(currency),
        accountId: accountId,
        startDate: start,
        deadlineDate: Value(deadline),
        description: Value(description),
      ),
    );

    return id;
  }

  /// Records a contribution toward the goal identified by [goalId].
  ///
  /// Unlike a withdrawal, there is no upper cap — saving beyond the target
  /// is ordinary (docs/adr/011-savings-goals.md §3).
  ///
  /// Throws [ArgumentError] if the amount is not positive, and [StateError]
  /// if the goal does not exist or is archived.
  Future<String> contribute({
    required String goalId,
    required int amountMinor,
    DateTime? date,
  }) async {
    if (amountMinor <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }

    final goal = await _dao.getById(goalId);
    if (goal == null) throw StateError('Savings goal not found: $goalId');
    if (goal.status == SavingsGoalStatus.archived) {
      throw StateError('This goal is archived');
    }

    final id = generateId();
    await _transactions.insertOne(
      TransactionsCompanion.insert(
        id: id,
        type: TransactionType.savingsContribution,
        amountMinor: amountMinor,
        currency: Value(goal.currency),
        accountId: goal.accountId,
        categoryId: const Value(null),
        savingsGoalId: Value(goalId),
        date: _dayStart(date ?? DateTime.now()),
        description: Value('Contribution · ${goal.name}'),
      ),
    );
    return id;
  }

  /// Records an early withdrawal from the goal identified by [goalId] —
  /// money returning to its linked account.
  ///
  /// Throws [ArgumentError] if the amount is not positive or exceeds what is
  /// currently saved, and [StateError] if the goal does not exist or is
  /// archived.
  Future<String> withdraw({
    required String goalId,
    required int amountMinor,
    DateTime? date,
  }) async {
    if (amountMinor <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }

    final goal = await _dao.getById(goalId);
    if (goal == null) throw StateError('Savings goal not found: $goalId');
    if (goal.status == SavingsGoalStatus.archived) {
      throw StateError('This goal is archived');
    }

    final progress = await progressFor(goal);
    // Over-withdrawal is rejected rather than silently clamped
    // (docs/adr/011-savings-goals.md §3).
    if (amountMinor > progress.currentAmountMinor) {
      throw ArgumentError(
        'That is more than the '
        '${_formatAmount(progress.currentAmountMinor)} currently saved',
      );
    }

    final id = generateId();
    await _transactions.insertOne(
      TransactionsCompanion.insert(
        id: id,
        type: TransactionType.savingsWithdrawal,
        amountMinor: amountMinor,
        currency: Value(goal.currency),
        accountId: goal.accountId,
        categoryId: const Value(null),
        savingsGoalId: Value(goalId),
        date: _dayStart(date ?? DateTime.now()),
        description: Value('Withdrawal · ${goal.name}'),
      ),
    );
    return id;
  }

  /// Updates the editable fields of a savings goal.
  ///
  /// The linked account and currency are fixed at creation: changing them
  /// would leave every recorded contribution/withdrawal describing a goal
  /// that no longer exists. The target amount and deadline are freely
  /// editable — unlike a loan's principal or an investment's amount, the
  /// target is only ever compared against the derived current amount, never
  /// summed into it, so changing it cannot corrupt anything derived.
  Future<void> update({
    required String id,
    required String name,
    required int targetAmountMinor,
    DateTime? deadlineDate,
    String description = '',
  }) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Savings goal not found: $id');

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Enter a name for this goal');
    }
    if (targetAmountMinor <= 0) {
      throw ArgumentError('Target amount must be greater than zero');
    }
    final deadline = deadlineDate == null ? null : _dayStart(deadlineDate);
    if (deadline != null && deadline.isBefore(row.startDate)) {
      throw ArgumentError('The deadline must be on or after the start date');
    }

    await _dao.updateOne(
      row.copyWith(
        name: trimmedName,
        targetAmountMinor: targetAmountMinor,
        deadlineDate: Value(deadline),
        description: description,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Archives a savings goal, keeping it and its transactions for reference.
  ///
  /// Reversible from any state, including once achieved — the same as
  /// [LoanController.archive] treats a paid-off loan.
  Future<void> archive(String id) =>
      _dao.updateStatus(id, SavingsGoalStatus.archived);

  /// Re-activates an archived savings goal.
  Future<void> restore(String id) =>
      _dao.updateStatus(id, SavingsGoalStatus.active);

  /// Permanently deletes a savings goal that has no contributions or
  /// withdrawals recorded.
  ///
  /// Unlike loans/investments, creating a goal never inserts a transaction
  /// (docs/adr/011-savings-goals.md §5), so there is no automatic-origination
  /// exception to the guard: any movement at all blocks deletion. Archiving
  /// is the correct way to retire a goal with history (docs/DATA_MODEL.md
  /// §47).
  Future<void> delete(String id) async {
    final goal = await _dao.getById(id);
    if (goal == null) throw StateError('Savings goal not found: $id');

    final hasMovements = await _transactions.hasAnySavingsGoalMovement(id);
    if (hasMovements) {
      throw ArgumentError(
        'This goal has contributions or withdrawals recorded. Archive it '
        'instead of deleting it.',
      );
    }

    await _database.transaction(() async {
      await _transactions.deleteForSavingsGoal(id);
      await _dao.deleteOne(id);
    });
  }

  /// Returns the savings goal identified by [id], or `null` if not found.
  Future<SavingsGoalRow?> getById(String id) => _dao.getById(id);

  /// Derives everything about [goal] that depends on its transactions.
  Future<SavingsGoalProgress> progressFor(SavingsGoalRow goal) async {
    final contributedMinor = await _transactions.savingsGoalMovementTotal(
      goal.id,
      TransactionType.savingsContribution,
    );
    final withdrawnMinor = await _transactions.savingsGoalMovementTotal(
      goal.id,
      TransactionType.savingsWithdrawal,
    );

    return SavingsGoalProgress(
      goal: goal,
      contributedMinor: contributedMinor,
      withdrawnMinor: withdrawnMinor,
    );
  }

  Future<void> _requireActiveAccount(String accountId) async {
    final account = await _accounts.getById(accountId);
    if (account == null) throw StateError('Account not found: $accountId');
    if (account.status != AccountStatus.active) {
      throw StateError('Account is not active: ${account.name}');
    }
  }

  // Minor units are formatted at the presentation boundary; the message only
  // needs the magnitude, so this stays currency-symbol free (the same
  // reasoning `LoanController._formatOutstanding` follows).
  static String _formatAmount(int amountMinor) {
    final major = amountMinor / 100;
    return major.toStringAsFixed(2);
  }

  static DateTime _dayStart(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
