import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../../accounts/data/account_dao.dart';
import '../../accounts/domain/account_status.dart';
import '../../categories/data/category_dao.dart';
import '../../categories/domain/category_status.dart';
import '../../categories/domain/category_type.dart';
import '../data/transaction_dao.dart';
import '../domain/transaction_type.dart';

/// Application-service for the transaction lifecycle.
///
/// Sits between the presentation layer and the data layer: it owns business
/// rules (ID generation, validation, which fields an update may change) and
/// keeps screens free of database and domain concerns. Mutations are
/// intentionally non-reactive — screens call these methods and rely on
/// [TransactionDao.watchAll] stream to refresh automatically.
///
/// Validation follows docs/DATA_MODEL.md §43 and §46:
/// * amount must be > 0
/// * the account must exist
/// * a transfer needs a valid, different destination account and no category
/// * income/expense categories, when provided, must exist and match the type
class TransactionController {
  TransactionController(this._dao, this._accounts, this._categories);

  final TransactionDao _dao;
  final AccountDao _accounts;
  final CategoryDao _categories;

  /// Creates a new transaction with a fresh ULID.
  ///
  /// [amountMinor] must be a positive integer. Returns the generated id so
  /// callers can navigate straight to the new transaction if needed.
  Future<String> create({
    required TransactionType type,
    required int amountMinor,
    required String accountId,
    String? destinationAccountId,
    String? categoryId,
    DateTime? date,
    String description = '',
    String currency = 'BDT',
  }) async {
    await _validate(
      type: type,
      amountMinor: amountMinor,
      accountId: accountId,
      destinationAccountId: destinationAccountId,
      categoryId: categoryId,
    );

    final id = generateId();
    await _dao.insertOne(
      TransactionsCompanion.insert(
        id: id,
        type: type,
        amountMinor: amountMinor,
        currency: Value(currency),
        accountId: accountId,
        destinationAccountId: Value(destinationAccountId),
        categoryId: Value(categoryId),
        date: date ?? DateTime.now(),
        description: Value(description),
      ),
    );
    return id;
  }

  /// Updates the editable fields of the transaction identified by [id].
  ///
  /// Touches [TransactionRow.updatedAt] so consumers can sort by "most recently
  /// changed". Throws [StateError] if no such transaction exists.
  Future<void> update({
    required String id,
    required TransactionType type,
    required int amountMinor,
    required String accountId,
    String? destinationAccountId,
    String? categoryId,
    required DateTime date,
    String description = '',
  }) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Transaction not found: $id');

    await _validate(
      type: type,
      amountMinor: amountMinor,
      accountId: accountId,
      destinationAccountId: destinationAccountId,
      categoryId: categoryId,
    );

    await _dao.updateOne(
      row.copyWith(
        type: type,
        amountMinor: amountMinor,
        accountId: accountId,
        destinationAccountId: Value(destinationAccountId),
        categoryId: Value(categoryId),
        date: date,
        description: description,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Permanently deletes a transaction by [id].
  ///
  /// Actual transaction deletion may be allowed so users can correct accidental
  /// entries (docs/DATA_MODEL.md §47).
  Future<void> delete(String id) => _dao.deleteOne(id);

  /// Returns the transaction identified by [id], or `null` if not found.
  Future<TransactionRow?> getById(String id) => _dao.getById(id);

  /// Validates a transaction's invariants before persistence.
  ///
  /// Throws [ArgumentError] with a user-readable message when a rule is
  /// violated; throws [StateError] when a referenced account or category is
  /// missing.
  Future<void> _validate({
    required TransactionType type,
    required int amountMinor,
    required String accountId,
    String? destinationAccountId,
    String? categoryId,
  }) async {
    if (amountMinor <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }

    final account = await _accounts.getById(accountId);
    if (account == null) {
      throw StateError('Account not found: $accountId');
    }
    if (account.status != AccountStatus.active) {
      throw StateError('Account is not active: ${account.name}');
    }

    if (type == TransactionType.transfer) {
      final destination = destinationAccountId;
      if (destination == null || destination.isEmpty) {
        throw ArgumentError('A transfer needs a destination account');
      }
      if (destination == accountId) {
        throw ArgumentError('Source and destination must be different');
      }
      final destinationRow = await _accounts.getById(destination);
      if (destinationRow == null) {
        throw StateError('Destination account not found: $destination');
      }
      if (destinationRow.status != AccountStatus.active) {
        throw StateError(
          'Destination account is not active: ${destinationRow.name}',
        );
      }
      if (categoryId != null) {
        throw ArgumentError('Transfers cannot have a category');
      }
      return;
    }

    // Income/expense — category is optional, but when present it must exist,
    // be active, and be compatible with the transaction type.
    if (categoryId != null) {
      final category = await _categories.getById(categoryId);
      if (category == null) {
        throw StateError('Category not found: $categoryId');
      }
      if (category.status != CategoryStatus.active) {
        throw StateError('Category is not active: ${category.name}');
      }
      final expected = type == TransactionType.income
          ? CategoryType.income
          : CategoryType.expense;
      if (category.type != expected) {
        throw ArgumentError(
          'Category "${category.name}" is not valid for '
          '${type.name} transactions',
        );
      }
    }
  }
}
