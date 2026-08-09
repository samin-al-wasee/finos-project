import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../accounts/data/account_table.dart';
import '../domain/account_status.dart';

part 'account_dao.g.dart';

/// Data-access object for financial accounts.
///
/// Sits between the application layer and the Drift database; keeps UI and
/// domain code free of table/query details.
@DriftAccessor(tables: [FinancialAccounts])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.db);

  /// All accounts, ordered by creation time (streaming).
  Stream<List<FinancialAccountRow>> watchAll() => (select(
    financialAccounts,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();

  /// All accounts, ordered by creation time (one-shot query).
  Future<List<FinancialAccountRow>> getAll() => (select(
    financialAccounts,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  /// Persists a new account row.
  Future<void> insertOne(FinancialAccountsCompanion entry) =>
      into(financialAccounts).insert(entry);

  /// Returns a single account by its [id], or `null` if not found.
  Future<FinancialAccountRow?> getById(String id) => (select(
    financialAccounts,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Replaces the entire row for an existing account.
  ///
  /// `replace` derives the WHERE clause from the row's primary key, so no
  /// explicit condition is needed.
  Future<void> updateOne(FinancialAccountRow row) =>
      (update(financialAccounts)).replace(row);

  /// Transitions the lifecycle [status] of the account identified by [id].
  ///
  /// Throws [StateError] if no account with that [id] exists.
  Future<void> updateStatus(String id, AccountStatus status) async {
    final account = await getById(id);
    if (account == null) throw StateError('Account not found: $id');
    await updateOne(account.copyWith(status: status));
  }
}
