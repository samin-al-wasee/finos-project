import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/period_totals.dart';
import '../domain/transaction_type.dart';
import 'transaction_table.dart';

part 'transaction_dao.g.dart';

/// Data-access object for financial transactions.
///
/// Sits between the application layer and the Drift database; keeps UI and
/// domain code free of table/query details.
@DriftAccessor(tables: [Transactions])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  /// All transactions, newest first (streaming).
  ///
  /// Ordered by the financial event [Transactions.date] descending so recent
  /// activity surfaces at the top of the list.
  Stream<List<TransactionRow>> watchAll() => (select(
    transactions,
  )..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();

  /// All transactions, newest first (one-shot query).
  Future<List<TransactionRow>> getAll() =>
      (select(transactions)..orderBy([(t) => OrderingTerm.desc(t.date)])).get();

  /// Persists a new transaction row.
  Future<void> insertOne(TransactionsCompanion entry) =>
      into(transactions).insert(entry);

  /// Returns a single transaction by its [id], or `null` if not found.
  Future<TransactionRow?> getById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Replaces the entire row for an existing transaction.
  ///
  /// `replace` derives the WHERE clause from the row's primary key, so no
  /// explicit condition is needed.
  Future<void> updateOne(TransactionRow row) =>
      (update(transactions)).replace(row);

  /// Permanently deletes a transaction by [id].
  ///
  /// Actual transaction deletion may be allowed so users can correct accidental
  /// entries (docs/DATA_MODEL.md §47); this must update derived calculations.
  Future<void> deleteOne(String id) async {
    await (delete(transactions)..where((t) => t.id.equals(id))).go();
  }

  /// Net balance impact of every transaction touching [accountId].
  ///
  /// Income and incoming transfers add to the balance; expenses and outgoing
  /// transfers subtract from it. Returns 0 for an account with no transactions.
  ///
  /// This is a derived value (docs/DATA_MODEL.md §45) computed from the
  /// transaction table rather than stored alongside the account.
  Future<int> balanceImpactFor(String accountId) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(
        CASE
          WHEN type = '${TransactionType.income.name.toUpperCase()}' THEN amount_minor
          WHEN type = '${TransactionType.expense.name.toUpperCase()}' THEN -amount_minor
          WHEN type = '${TransactionType.transfer.name.toUpperCase()}'
               AND account_id = ? THEN -amount_minor
          WHEN type = '${TransactionType.transfer.name.toUpperCase()}'
               AND destination_account_id = ? THEN amount_minor
          ELSE 0
        END
      ), 0) AS impact
      FROM transactions
      WHERE account_id = ? OR destination_account_id = ?
      ''',
      variables: [
        Variable(accountId),
        Variable(accountId),
        Variable(accountId),
        Variable(accountId),
      ],
    ).getSingle();

    return row.read<int>('impact');
  }

  /// Sums income and expense for transactions dated `from <= date < to`
  /// (half-open range).
  ///
  /// Transfers are excluded — they move money between accounts and are neither
  /// income nor expense (docs/DATA_MODEL.md §17).
  Future<PeriodTotals> totalsForPeriod(DateTime from, DateTime to) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(
        CASE WHEN type = '${TransactionType.income.name.toUpperCase()}'
             THEN amount_minor ELSE 0 END
      ), 0) AS income,
      COALESCE(SUM(
        CASE WHEN type = '${TransactionType.expense.name.toUpperCase()}'
             THEN amount_minor ELSE 0 END
      ), 0) AS expense
      FROM transactions
      WHERE date >= ? AND date < ?
      ''',
      variables: [Variable(from), Variable(to)],
    ).getSingle();

    return PeriodTotals(
      incomeMinor: row.read<int>('income'),
      expenseMinor: row.read<int>('expense'),
    );
  }

  /// Sum of balance impact across all accounts.
  ///
  /// Transfers net to zero globally (source −amount, destination +amount), so
  /// this equals total income minus total expense. Returns 0 for an empty
  /// table.
  Future<int> totalBalanceImpact() async {
    final row = await customSelect('''
      SELECT COALESCE(SUM(
        CASE
          WHEN type = '${TransactionType.income.name.toUpperCase()}' THEN amount_minor
          WHEN type = '${TransactionType.expense.name.toUpperCase()}' THEN -amount_minor
          ELSE 0
        END
      ), 0) AS impact
      FROM transactions
      ''').getSingle();

    return row.read<int>('impact');
  }
}
