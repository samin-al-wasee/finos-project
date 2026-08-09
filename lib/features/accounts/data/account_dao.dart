import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../accounts/data/account_table.dart';

part 'account_dao.g.dart';

/// Data-access object for financial accounts.
///
/// Sits between the application layer and the Drift database; keeps UI and
/// domain code free of table/query details.
@DriftAccessor(tables: [FinancialAccounts])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.db);

  /// All accounts, ordered by creation time.
  Stream<List<FinancialAccountRow>> watchAll() => (select(
    financialAccounts,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();

  /// Persists a new account row.
  Future<void> insertOne(FinancialAccountsCompanion entry) =>
      into(financialAccounts).insert(entry);
}
