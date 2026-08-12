import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'template_table.dart';

part 'template_dao.g.dart';

/// Data-access object for transaction templates (docs/ROADMAP.md §8.2).
@DriftAccessor(tables: [TransactionTemplates])
class TemplateDao extends DatabaseAccessor<AppDatabase>
    with _$TemplateDaoMixin {
  TemplateDao(super.db);

  /// Stream all templates, ordered by name.
  Stream<List<TransactionTemplateRow>> watchAll() {
    return (select(
      transactionTemplates,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  }

  /// One-shot fetch of all templates, ordered by name.
  Future<List<TransactionTemplateRow>> getAll() {
    return (select(
      transactionTemplates,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  /// Get a single template by ID. Returns `null` if not found.
  Future<TransactionTemplateRow?> getById(String id) {
    return (select(
      transactionTemplates,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Persists a new template row.
  Future<void> insertOne(TransactionTemplatesCompanion entry) =>
      into(transactionTemplates).insert(entry);

  /// Replaces the entire row for an existing template.
  ///
  /// `replace` derives the WHERE clause from the row's primary key, so no
  /// explicit condition is needed.
  Future<void> updateOne(TransactionTemplateRow row) =>
      (update(transactionTemplates)).replace(row);

  /// Permanently deletes a template by [id].
  ///
  /// A template is only ever a preset for manual entry, not a financial
  /// record, so deleting one has no effect on any existing transaction
  /// (docs/ROADMAP.md §8.2).
  Future<void> deleteOne(String id) async {
    await (delete(transactionTemplates)..where((t) => t.id.equals(id))).go();
  }
}
