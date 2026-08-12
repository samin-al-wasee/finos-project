import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../../transactions/domain/transaction_type.dart';
import '../data/template_dao.dart';

/// Application service for the transaction template lifecycle
/// (docs/ROADMAP.md §8.2).
///
/// A template is a preset for manual entry, not a financial record — creating,
/// editing, or deleting one never touches a transaction or an account balance.
class TemplateController {
  TemplateController(this._dao);

  final TemplateDao _dao;

  /// Creates a new template with a fresh ULID.
  ///
  /// Returns the generated ID.
  ///
  /// Throws [ArgumentError] for an empty name, a non-positive preset amount,
  /// or a transfer whose preset source and destination account are the same.
  Future<String> create({
    required String name,
    required TransactionType type,
    int? amountMinor,
    String? accountId,
    String? destinationAccountId,
    String? categoryId,
    String description = '',
  }) async {
    final trimmedName = _validate(
      name: name,
      type: type,
      amountMinor: amountMinor,
      accountId: accountId,
      destinationAccountId: destinationAccountId,
    );

    final id = generateId();
    await _dao.insertOne(
      TransactionTemplatesCompanion.insert(
        id: id,
        name: trimmedName,
        type: type,
        amountMinor: Value(amountMinor),
        accountId: Value(accountId),
        destinationAccountId: Value(
          type == TransactionType.transfer ? destinationAccountId : null,
        ),
        categoryId: Value(type == TransactionType.transfer ? null : categoryId),
        description: Value(description.trim()),
      ),
    );
    return id;
  }

  /// Updates an existing template. Same validation as [create].
  ///
  /// Throws [StateError] if the template doesn't exist.
  Future<void> update({
    required String id,
    required String name,
    required TransactionType type,
    int? amountMinor,
    String? accountId,
    String? destinationAccountId,
    String? categoryId,
    String description = '',
  }) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Template not found: $id');

    final trimmedName = _validate(
      name: name,
      type: type,
      amountMinor: amountMinor,
      accountId: accountId,
      destinationAccountId: destinationAccountId,
    );

    await _dao.updateOne(
      row.copyWith(
        name: trimmedName,
        type: type,
        amountMinor: Value(amountMinor),
        accountId: Value(accountId),
        destinationAccountId: Value(
          type == TransactionType.transfer ? destinationAccountId : null,
        ),
        categoryId: Value(type == TransactionType.transfer ? null : categoryId),
        description: description.trim(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Permanently deletes a template.
  Future<void> delete(String id) => _dao.deleteOne(id);

  String _validate({
    required String name,
    required TransactionType type,
    required int? amountMinor,
    required String? accountId,
    required String? destinationAccountId,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Enter a name for this template');
    }
    if (amountMinor != null && amountMinor <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }
    if (type == TransactionType.transfer &&
        accountId != null &&
        accountId == destinationAccountId) {
      throw ArgumentError('The destination must differ from the source');
    }
    return trimmedName;
  }
}
