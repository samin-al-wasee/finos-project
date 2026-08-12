import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../../budgets/domain/budget_period.dart' show dayStart;
import '../../transactions/data/transaction_dao.dart';
import '../../transactions/domain/transaction_type.dart';
import '../data/recurring_transaction_dao.dart';
import '../domain/due_occurrences.dart';
import '../domain/recurrence_frequency.dart';
import '../domain/recurring_status.dart';

/// Application service for the recurring transaction lifecycle
/// (docs/ROADMAP.md §8.1).
///
/// A rule is not itself a transaction (docs/DATA_MODEL.md §28) — confirming a
/// due occurrence is what creates one. Nothing here ever creates a
/// transaction without that explicit confirmation: the rule only tracks what
/// is due, never generates silently (docs/ARCHITECTURE.md §20).
class RecurringTransactionController {
  RecurringTransactionController(
    this._database,
    this._dao,
    this._transactionDao,
  );

  final AppDatabase _database;
  final RecurringTransactionDao _dao;
  final TransactionDao _transactionDao;

  /// Creates a new rule with a fresh ULID.
  ///
  /// The rule's first due date is [startDate] itself — a rule effective today
  /// is due today, the same convention budgets and loans use for their own
  /// start dates.
  ///
  /// Returns the generated ID.
  Future<String> create({
    required String name,
    required TransactionType type,
    required int amountMinor,
    required String accountId,
    String? destinationAccountId,
    String? categoryId,
    String description = '',
    required RecurrenceFrequency frequency,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final trimmedName = _validate(
      name: name,
      type: type,
      amountMinor: amountMinor,
      accountId: accountId,
      destinationAccountId: destinationAccountId,
    );

    final start = dayStart(startDate);
    final end = endDate == null ? null : dayStart(endDate);
    if (end != null && end.isBefore(start)) {
      throw ArgumentError('The end date must be on or after the start date');
    }

    final id = generateId();
    await _dao.insertOne(
      RecurringTransactionsCompanion.insert(
        id: id,
        name: trimmedName,
        type: type,
        amountMinor: amountMinor,
        accountId: accountId,
        destinationAccountId: Value(
          type == TransactionType.transfer ? destinationAccountId : null,
        ),
        categoryId: Value(type == TransactionType.transfer ? null : categoryId),
        description: Value(description.trim()),
        frequency: frequency,
        startDate: start,
        nextOccurrence: start,
        endDate: Value(end),
      ),
    );
    return id;
  }

  /// Updates a rule's details. Leaves `nextOccurrence` untouched — scheduling
  /// state is only ever advanced by [confirmNext], [confirmAll], or
  /// [skipAll], never by editing the rule.
  ///
  /// Throws [StateError] if the rule doesn't exist.
  Future<void> update({
    required String id,
    required String name,
    required TransactionType type,
    required int amountMinor,
    required String accountId,
    String? destinationAccountId,
    String? categoryId,
    String description = '',
    required RecurrenceFrequency frequency,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Recurring transaction not found: $id');

    final trimmedName = _validate(
      name: name,
      type: type,
      amountMinor: amountMinor,
      accountId: accountId,
      destinationAccountId: destinationAccountId,
    );

    final start = dayStart(startDate);
    final end = endDate == null ? null : dayStart(endDate);
    if (end != null && end.isBefore(start)) {
      throw ArgumentError('The end date must be on or after the start date');
    }

    await _dao.updateOne(
      row.copyWith(
        name: trimmedName,
        type: type,
        amountMinor: amountMinor,
        accountId: accountId,
        destinationAccountId: Value(
          type == TransactionType.transfer ? destinationAccountId : null,
        ),
        categoryId: Value(type == TransactionType.transfer ? null : categoryId),
        description: description.trim(),
        frequency: frequency,
        startDate: start,
        endDate: Value(end),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> archive(String id) =>
      _dao.updateStatus(id, RecurringStatus.archived);

  Future<void> restore(String id) =>
      _dao.updateStatus(id, RecurringStatus.active);

  Future<void> delete(String id) => _dao.deleteOne(id);

  /// Confirms just the oldest due occurrence: creates its transaction and
  /// advances `nextOccurrence` to the one after it.
  ///
  /// Does nothing if the rule has no due occurrence. Throws [StateError] if
  /// the rule doesn't exist.
  Future<void> confirmNext(String id) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Recurring transaction not found: $id');

    final due = dueOccurrences(
      from: row.nextOccurrence,
      frequency: row.frequency,
      asOf: DateTime.now(),
      endDate: row.endDate,
    );
    if (due.dates.isEmpty) return;

    await _database.transaction(() async {
      await _createTransaction(row, due.dates.first);
      await _dao.updateOne(
        row.copyWith(
          nextOccurrence: nextOccurrence(due.dates.first, row.frequency),
          updatedAt: DateTime.now(),
        ),
      );
    });
  }

  /// Confirms every currently-due occurrence (capped at [maxDueOccurrences]):
  /// creates a transaction for each and advances `nextOccurrence` past the
  /// last one — atomically, so a rule can never end up with some of the
  /// backlog created and the rest lost.
  ///
  /// Does nothing if the rule has no due occurrence. Throws [StateError] if
  /// the rule doesn't exist.
  Future<void> confirmAll(String id) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Recurring transaction not found: $id');

    final due = dueOccurrences(
      from: row.nextOccurrence,
      frequency: row.frequency,
      asOf: DateTime.now(),
      endDate: row.endDate,
    );
    if (due.dates.isEmpty) return;

    await _database.transaction(() async {
      for (final date in due.dates) {
        await _createTransaction(row, date);
      }
      await _dao.updateOne(
        row.copyWith(
          nextOccurrence: nextOccurrence(due.dates.last, row.frequency),
          updatedAt: DateTime.now(),
        ),
      );
    });
  }

  /// Skips every currently-due occurrence (capped at [maxDueOccurrences]):
  /// advances `nextOccurrence` past the last one without creating any
  /// transaction.
  ///
  /// Does nothing if the rule has no due occurrence. Throws [StateError] if
  /// the rule doesn't exist.
  Future<void> skipAll(String id) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Recurring transaction not found: $id');

    final due = dueOccurrences(
      from: row.nextOccurrence,
      frequency: row.frequency,
      asOf: DateTime.now(),
      endDate: row.endDate,
    );
    if (due.dates.isEmpty) return;

    await _dao.updateOne(
      row.copyWith(
        nextOccurrence: nextOccurrence(due.dates.last, row.frequency),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _createTransaction(RecurringTransactionRow rule, DateTime date) {
    return _transactionDao.insertOne(
      TransactionsCompanion.insert(
        id: generateId(),
        type: rule.type,
        amountMinor: rule.amountMinor,
        accountId: rule.accountId,
        destinationAccountId: Value(rule.destinationAccountId),
        categoryId: Value(rule.categoryId),
        date: date,
        description: Value(
          rule.description.isNotEmpty ? rule.description : rule.name,
        ),
      ),
    );
  }

  String _validate({
    required String name,
    required TransactionType type,
    required int amountMinor,
    required String accountId,
    required String? destinationAccountId,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Enter a name for this recurring transaction');
    }
    if (amountMinor <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }
    if (type == TransactionType.transfer) {
      if (destinationAccountId == null) {
        throw ArgumentError('Select a destination account');
      }
      if (destinationAccountId == accountId) {
        throw ArgumentError('The destination must differ from the source');
      }
    }
    return trimmedName;
  }
}
