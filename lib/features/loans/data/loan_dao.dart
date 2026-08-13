import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/loan_status.dart';
import 'loan_table.dart';

part 'loan_dao.g.dart';

/// Data-access object for loans (docs/DATA_MODEL.md §29–§33).
///
/// Only the loan record lives here. Repayments are transactions, so the money and
/// everything derived from it is queried through [TransactionDao] (ADR-004).
@DriftAccessor(tables: [Loans])
class LoanDao extends DatabaseAccessor<AppDatabase> with _$LoanDaoMixin {
  LoanDao(super.db);

  /// Stream all loans, newest first, including archived ones.
  Stream<List<LoanRow>> watchAll() =>
      (select(loans)..orderBy([(t) => OrderingTerm.desc(t.startDate)])).watch();

  /// One-shot fetch of all loans, newest first, including archived ones.
  Future<List<LoanRow>> getAll() =>
      (select(loans)..orderBy([(t) => OrderingTerm.desc(t.startDate)])).get();

  /// Returns a single loan by its [id], or `null` if not found.
  Future<LoanRow?> getById(String id) =>
      (select(loans)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Persists a new loan row.
  Future<void> insertOne(LoansCompanion entry) => into(loans).insert(entry);

  /// Replaces the entire row for an existing loan.
  Future<void> updateOne(LoanRow row) => (update(loans)).replace(row);

  /// Permanently deletes a loan by [id].
  ///
  /// The caller must remove the loan's transactions in the same database
  /// transaction; the foreign key on `transactions.loan_id` otherwise blocks this.
  Future<void> deleteOne(String id) async {
    await (delete(loans)..where((t) => t.id.equals(id))).go();
  }

  /// Transitions the lifecycle [status] of the loan identified by [id].
  ///
  /// Throws [StateError] if no loan with that [id] exists.
  Future<void> updateStatus(String id, LoanStatus status) async {
    final loan = await getById(id);
    if (loan == null) throw StateError('Loan not found: $id');
    await updateOne(loan.copyWith(status: status, updatedAt: DateTime.now()));
  }

  /// Whether any other loan's `group_id` points at [id] — i.e. whether [id] is
  /// a relationship root with at least one linked extension.
  ///
  /// Used only by the delete guard (docs/adr/006-loan-relationships.md): a root
  /// with linked children must be archived rather than deleted.
  Future<bool> hasGroupChildren(String id) async {
    final count = countAll();
    final query = selectOnly(loans)
      ..addColumns([count])
      ..where(loans.groupId.equals(id));
    final row = await query.getSingle();
    return (row.read(count) ?? 0) > 0;
  }
}
