import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../../accounts/data/account_dao.dart';
import '../domain/account_status.dart';
import '../domain/account_type.dart';

/// Application-service for the account lifecycle.
///
/// Sits between the presentation layer and the data layer: it owns business
/// rules (ID generation, which fields an update may change, lifecycle
/// transitions) and keeps screens free of database and domain concerns.
/// Mutations are intentionally non-reactive — screens call these methods and
/// rely on [AccountDao.watchAll] stream to refresh automatically.
class AccountController {
  AccountController(this._dao);

  final AccountDao _dao;

  /// Creates a new account with a fresh ULID and the default status.
  ///
  /// [currency] defaults to the table default (`BDT`). Returns the generated
  /// id so callers can navigate straight to the new account if needed.
  Future<String> create({
    required String name,
    required AccountType type,
    String currency = 'BDT',
    int openingBalanceMinor = 0,
  }) async {
    final id = generateId();
    await _dao.insertOne(
      FinancialAccountsCompanion.insert(
        id: id,
        name: name,
        type: type,
        currency: Value(currency),
        openingBalanceMinor: Value(openingBalanceMinor),
      ),
    );
    return id;
  }

  /// Updates the editable fields of the account identified by [id].
  ///
  /// Touches [FinancialAccountRow.updatedAt] so consumers can sort by "most
  /// recently changed". Throws [StateError] if no such account exists.
  Future<void> update({
    required String id,
    required String name,
    required AccountType type,
    required String currency,
    required int openingBalanceMinor,
  }) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Account not found: $id');
    await _dao.updateOne(
      row.copyWith(
        name: name,
        type: type,
        currency: currency,
        openingBalanceMinor: openingBalanceMinor,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Archives the account — soft-deletes it without destroying history.
  ///
  /// Throws [StateError] if no such account exists.
  Future<void> archive(String id) =>
      _dao.updateStatus(id, AccountStatus.archived);

  /// Re-activates a previously archived account.
  ///
  /// Throws [StateError] if no such account exists.
  Future<void> restore(String id) =>
      _dao.updateStatus(id, AccountStatus.active);

  /// Returns the account identified by [id], or `null` if not found.
  Future<FinancialAccountRow?> getById(String id) => _dao.getById(id);
}
