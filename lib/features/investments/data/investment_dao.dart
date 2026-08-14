import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/investment_status.dart';
import 'investment_table.dart';

part 'investment_dao.g.dart';

/// Data-access object for investments (docs/adr/009-investment-accounting.md).
///
/// Only the investment record lives here. Contributions and payouts are
/// transactions, so the money and everything derived from it is queried
/// through `TransactionDao`, the same split `LoanDao` uses for loans.
@DriftAccessor(tables: [Investments])
class InvestmentDao extends DatabaseAccessor<AppDatabase>
    with _$InvestmentDaoMixin {
  InvestmentDao(super.db);

  /// Stream all investments, newest first, including archived ones.
  Stream<List<InvestmentRow>> watchAll() => (select(
    investments,
  )..orderBy([(t) => OrderingTerm.desc(t.startDate)])).watch();

  /// One-shot fetch of all investments, newest first, including archived ones.
  Future<List<InvestmentRow>> getAll() => (select(
    investments,
  )..orderBy([(t) => OrderingTerm.desc(t.startDate)])).get();

  /// Returns a single investment by its [id], or `null` if not found.
  Future<InvestmentRow?> getById(String id) =>
      (select(investments)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Persists a new investment row.
  Future<void> insertOne(InvestmentsCompanion entry) =>
      into(investments).insert(entry);

  /// Replaces the entire row for an existing investment.
  Future<void> updateOne(InvestmentRow row) =>
      (update(investments)).replace(row);

  /// Permanently deletes an investment by [id].
  ///
  /// The caller must remove the investment's transactions in the same
  /// database transaction; the foreign key on `transactions.investment_id`
  /// otherwise blocks this.
  Future<void> deleteOne(String id) async {
    await (delete(investments)..where((t) => t.id.equals(id))).go();
  }

  /// Transitions the lifecycle [status] of the investment identified by [id].
  ///
  /// Throws [StateError] if no investment with that [id] exists.
  Future<void> updateStatus(String id, InvestmentStatus status) async {
    final investment = await getById(id);
    if (investment == null) throw StateError('Investment not found: $id');
    await updateOne(
      investment.copyWith(status: status, updatedAt: DateTime.now()),
    );
  }
}
