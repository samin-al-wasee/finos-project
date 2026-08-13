import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'credit_card_details_table.dart';

part 'credit_card_dao.g.dart';

/// Data-access object for credit card billing details
/// (docs/DATA_MODEL.md §60).
///
/// Only the billing details live here. Everything about the current cycle is
/// derived from the account's transactions, so it is queried through
/// [TransactionDao] instead (ADR-005, mirroring ADR-004 for loans).
@DriftAccessor(tables: [CreditCardDetails])
class CreditCardDao extends DatabaseAccessor<AppDatabase>
    with _$CreditCardDaoMixin {
  CreditCardDao(super.db);

  /// Streams the billing details for [accountId], or `null` while it has
  /// none.
  Stream<CreditCardDetailsRow?> watchByAccountId(String accountId) => (select(
    creditCardDetails,
  )..where((t) => t.accountId.equals(accountId))).watchSingleOrNull();

  /// One-shot fetch of the billing details for [accountId], or `null`.
  Future<CreditCardDetailsRow?> getByAccountId(String accountId) => (select(
    creditCardDetails,
  )..where((t) => t.accountId.equals(accountId))).getSingleOrNull();

  /// Persists a new billing-details row.
  Future<void> insertOne(CreditCardDetailsCompanion entry) =>
      into(creditCardDetails).insert(entry);

  /// Replaces the entire row for existing billing details.
  Future<void> updateOne(CreditCardDetailsRow row) =>
      (update(creditCardDetails)).replace(row);
}
