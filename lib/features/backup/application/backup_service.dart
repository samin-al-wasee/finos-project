import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../budgets/data/budget_dao.dart';
import '../../budgets/domain/budget_scope.dart';
import '../data/backup_serializer.dart';
import '../domain/backup_envelope.dart';

/// Reads and writes FinOS backups (FR-08, docs/ROADMAP.md §6.7).
///
/// The two operations have deliberately different risk profiles:
///
/// * **Export** is read-only and cannot damage anything.
/// * **Restore replaces every financial record.** It therefore parses and fully
///   validates the file *before* touching the database, then applies the whole
///   change inside a single transaction. Any failure — malformed field, broken
///   reference, database error — rolls back, leaving the existing data exactly as
///   it was (AGENTS.md §14).
///
/// User preferences are not part of a backup. They describe this device rather
/// than the user's finances, so restoring should not silently repaint the app or
/// change its currency (docs/DATA_MODEL.md §51).
class BackupService {
  BackupService(this._database);

  final AppDatabase _database;

  // ------------------------------------------------------------------
  // Export
  // ------------------------------------------------------------------

  /// Serialises every financial record into a backup document.
  ///
  /// [now] is injectable so tests can assert a fixed `exported_at`.
  Future<String> export({DateTime? now}) async {
    final accounts = await _database.select(_database.financialAccounts).get();
    final categories = await _database.select(_database.categories).get();
    final loans = await _database.select(_database.loans).get();
    final transactions = await _database.select(_database.transactions).get();
    final budgets = await _database.select(_database.budgets).get();
    final budgetDao = BudgetDao(_database);

    final document = <String, Object?>{
      BackupFormat.versionKey: BackupFormat.version,
      BackupFormat.schemaVersionKey: _database.schemaVersion,
      BackupFormat.exportedAtKey: (now ?? DateTime.now()).toIso8601String(),
      BackupFormat.accountsKey: accounts
          .map(BackupSerializer.accountToJson)
          .toList(),
      BackupFormat.categoriesKey: categories
          .map(BackupSerializer.categoryToJson)
          .toList(),
      BackupFormat.loansKey: loans.map(BackupSerializer.loanToJson).toList(),
      BackupFormat.transactionsKey: transactions
          .map(BackupSerializer.transactionToJson)
          .toList(),
      BackupFormat.budgetsKey: [
        for (final budget in budgets)
          BackupSerializer.budgetToJson(
            budget,
            categoryIds: budget.scopeType == BudgetScopeType.multiCategory
                ? await budgetDao.categoriesFor(budget.id)
                : const {},
          ),
      ],
    };

    // Indented so a user who opens the file can actually read it.
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// How many records are currently stored — used to warn before a restore
  /// replaces them.
  Future<BackupCounts> currentCounts() async {
    return BackupCounts(
      accounts: await _count(_database.financialAccounts),
      categories: await _count(_database.categories),
      transactions: await _count(_database.transactions),
      budgets: await _count(_database.budgets),
      loans: await _count(_database.loans),
    );
  }

  // ------------------------------------------------------------------
  // Import
  // ------------------------------------------------------------------

  /// Parses and validates [contents] without touching the database.
  ///
  /// Returns what the file contains, so callers can show the user the size of
  /// the change before committing to it. Throws [ValidationException] with a
  /// readable message if the file cannot be trusted.
  ParsedBackup parse(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const ValidationException(
        "This file isn't valid JSON, so it can't be a FinOS backup.",
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw const ValidationException(
        'This file does not look like a FinOS backup.',
      );
    }

    _validateHeader(decoded);

    final accounts = _readTable(
      decoded,
      BackupFormat.accountsKey,
      BackupSerializer.accountFromJson,
    );
    final categories = _readTable(
      decoded,
      BackupFormat.categoriesKey,
      BackupSerializer.categoryFromJson,
    );
    final loans = _readTable(
      decoded,
      BackupFormat.loansKey,
      BackupSerializer.loanFromJson,
    );
    final transactions = _readTable(
      decoded,
      BackupFormat.transactionsKey,
      BackupSerializer.transactionFromJson,
    );
    final (budgets, budgetCategoryIds) = _readBudgets(decoded);

    _validateUniqueIds(accounts.map((a) => a.id), 'account');
    _validateUniqueIds(categories.map((c) => c.id), 'category');
    _validateUniqueIds(loans.map((l) => l.id), 'loan');
    _validateUniqueIds(transactions.map((t) => t.id), 'transaction');
    _validateUniqueIds(budgets.map((b) => b.id), 'budget');

    _validateReferences(
      accounts: accounts,
      categories: categories,
      loans: loans,
      transactions: transactions,
      budgets: budgets,
      budgetCategoryIds: budgetCategoryIds,
    );

    return ParsedBackup(
      accounts: accounts,
      categories: categories,
      loans: loans,
      transactions: transactions,
      budgets: budgets,
      budgetCategoryIds: budgetCategoryIds,
    );
  }

  /// Reads the `budgets` table, pairing each row with its resolved
  /// `category_ids` (only ever non-empty for a `MULTI_CATEGORY` budget).
  ///
  /// A bespoke reader rather than [_readTable], because a budget's member
  /// categories live alongside it in the same JSON record, not in a separate
  /// top-level table (docs/adr/007-flexible-budget-scope.md) — [_readTable]
  /// only has room for one value per entry.
  (List<BudgetRow>, Map<String, Set<String>>) _readBudgets(
    Map<String, Object?> json,
  ) {
    final value = json[BackupFormat.budgetsKey];
    // A missing table is treated as empty: a backup taken before a feature
    // existed simply has nothing for it.
    if (value == null) return (const [], const {});
    if (value is! List) {
      throw ValidationException(
        'The "${BackupFormat.budgetsKey}" section of this backup is not a '
        'list.',
      );
    }

    final rows = <BudgetRow>[];
    final categoryIds = <String, Set<String>>{};
    for (var index = 0; index < value.length; index++) {
      final entry = value[index];
      if (entry is! Map<String, Object?>) {
        throw ValidationException(
          'Entry ${index + 1} in "${BackupFormat.budgetsKey}" is not a '
          'record.',
        );
      }
      try {
        final row = BackupSerializer.budgetFromJson(entry);
        rows.add(row);
        final ids = BackupSerializer.budgetCategoryIdsFromJson(entry);
        if (ids.isNotEmpty) categoryIds[row.id] = ids;
      } on ValidationException catch (error) {
        throw ValidationException(
          '${error.message} (entry ${index + 1} in '
          '"${BackupFormat.budgetsKey}")',
        );
      }
    }
    return (rows, categoryIds);
  }

  /// Replaces every financial record with the contents of [backup].
  ///
  /// Runs as one transaction: either the whole backup lands or nothing changes.
  /// Deletes run children-first and inserts parents-first so foreign keys hold
  /// at every point (docs/DATA_MODEL.md §44).
  ///
  /// Returns what was written.
  Future<BackupCounts> restore(ParsedBackup backup) async {
    try {
      await _database.transaction(() async {
        // Children first. Transactions reference accounts, categories, and
        // loans; loans reference accounts; budget_categories references
        // budgets and categories.
        await _database.delete(_database.budgetCategories).go();
        await _database.delete(_database.transactions).go();
        await _database.delete(_database.budgets).go();
        await _database.delete(_database.loans).go();
        await _database.delete(_database.categories).go();
        await _database.delete(_database.financialAccounts).go();

        // Parents first on the way back in. Within loans, `group_id` is a
        // same-table foreign key, so a root (no group_id) must land before any
        // loan that points at it — a naive backup file order (e.g. insertion
        // order from a different device) could otherwise place a child first
        // and fail the FK check. A stable partition is enough since a
        // relationship is always exactly one level deep
        // (docs/adr/006-loan-relationships.md).
        final orderedLoans = [
          ...backup.loans.where((l) => l.groupId == null),
          ...backup.loans.where((l) => l.groupId != null),
        ];

        // budget_categories is inserted last: it references both budgets and
        // categories, so both must already exist
        // (docs/adr/007-flexible-budget-scope.md).
        final budgetCategoryRows = [
          for (final entry in backup.budgetCategoryIds.entries)
            for (final categoryId in entry.value)
              BudgetCategoriesCompanion.insert(
                budgetId: entry.key,
                categoryId: categoryId,
              ),
        ];

        await _database.batch((b) {
          b.insertAll(_database.financialAccounts, backup.accounts);
          b.insertAll(_database.categories, backup.categories);
          b.insertAll(_database.loans, orderedLoans);
          b.insertAll(_database.transactions, backup.transactions);
          b.insertAll(_database.budgets, backup.budgets);
          b.insertAll(_database.budgetCategories, budgetCategoryRows);
        });
      });
    } on AppException {
      rethrow;
    } catch (_) {
      // The transaction has already rolled back; existing data is intact.
      // Nothing about the failure is logged, since it would carry financial
      // records (AGENTS.md §15).
      throw const PersistenceException(
        'The backup could not be restored, so nothing was changed. '
        'Your existing data is untouched.',
      );
    }
    return backup.counts;
  }

  /// Convenience for parse-then-restore in one step.
  Future<BackupCounts> importBackup(String contents) =>
      restore(parse(contents));

  // ------------------------------------------------------------------
  // Validation
  // ------------------------------------------------------------------

  void _validateHeader(Map<String, Object?> json) {
    final version = json[BackupFormat.versionKey];
    if (version == null) {
      throw const ValidationException(
        'This file does not look like a FinOS backup: it has no '
        'backup version.',
      );
    }
    if (version is! int) {
      throw const ValidationException(
        'This backup has an unreadable version, so it cannot be restored.',
      );
    }
    if (!BackupFormat.supportedVersions.contains(version)) {
      throw ValidationException(
        'This backup was written in format version $version, which this '
        'version of FinOS cannot read. Update the app and try again.',
      );
    }
  }

  /// Reads one table, wrapping each row's failure with its position.
  ///
  /// The index makes a bad record findable in a file with thousands of rows.
  List<T> _readTable<T>(
    Map<String, Object?> json,
    String key,
    T Function(Map<String, Object?>) fromJson,
  ) {
    final value = json[key];
    // A missing table is treated as empty: a backup taken before a feature
    // existed simply has nothing for it.
    if (value == null) return const [];
    if (value is! List) {
      throw ValidationException(
        'The "$key" section of this backup is not a list.',
      );
    }

    final rows = <T>[];
    for (var index = 0; index < value.length; index++) {
      final entry = value[index];
      if (entry is! Map<String, Object?>) {
        throw ValidationException(
          'Entry ${index + 1} in "$key" is not a record.',
        );
      }
      try {
        rows.add(fromJson(entry));
      } on ValidationException catch (error) {
        throw ValidationException(
          '${error.message} (entry ${index + 1} in "$key")',
        );
      }
    }
    return rows;
  }

  void _validateUniqueIds(Iterable<String> ids, String what) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) {
        throw ValidationException(
          'This backup lists the same $what twice (id "$id").',
        );
      }
    }
  }

  /// Checks that every reference resolves *within the backup*.
  ///
  /// A restore replaces everything, so a transaction pointing at an account the
  /// backup does not contain has nothing to attach to. Catching it here produces
  /// a readable message instead of an opaque foreign-key failure mid-restore.
  void _validateReferences({
    required List<FinancialAccountRow> accounts,
    required List<CategoryRow> categories,
    required List<LoanRow> loans,
    required List<TransactionRow> transactions,
    required List<BudgetRow> budgets,
    required Map<String, Set<String>> budgetCategoryIds,
  }) {
    final accountIds = accounts.map((a) => a.id).toSet();
    final categoryIds = categories.map((c) => c.id).toSet();
    final loanIds = loans.map((l) => l.id).toSet();

    for (final loan in loans) {
      final disbursement = loan.disbursementAccountId;
      if (disbursement != null && !accountIds.contains(disbursement)) {
        throw ValidationException(
          'A loan in this backup refers to an account that the backup does not '
          'contain (id "$disbursement").',
        );
      }
    }

    for (final transaction in transactions) {
      final loanId = transaction.loanId;
      if (loanId != null && !loanIds.contains(loanId)) {
        throw ValidationException(
          'A loan movement in this backup refers to a loan that the backup does '
          'not contain (id "$loanId").',
        );
      }
    }

    for (final transaction in transactions) {
      if (!accountIds.contains(transaction.accountId)) {
        throw ValidationException(
          'A transaction in this backup refers to an account that the backup '
          'does not contain (id "${transaction.accountId}").',
        );
      }
      final destination = transaction.destinationAccountId;
      if (destination != null && !accountIds.contains(destination)) {
        throw ValidationException(
          'A transfer in this backup refers to a destination account that the '
          'backup does not contain (id "$destination").',
        );
      }
      final category = transaction.categoryId;
      if (category != null && !categoryIds.contains(category)) {
        throw ValidationException(
          'A transaction in this backup refers to a category that the backup '
          'does not contain (id "$category").',
        );
      }
    }

    // A budget's referenced categories generalise from "its one category" to
    // its *resolved* category set (docs/adr/007-flexible-budget-scope.md):
    // empty for UNCATEGORIZED/WHOLE_ACCOUNT, one for SINGLE_CATEGORY, and
    // whatever `category_ids` lists for MULTI_CATEGORY.
    for (final budget in budgets) {
      final resolved = switch (budget.scopeType) {
        BudgetScopeType.singleCategory =>
          budget.categoryId == null ? const <String>{} : {budget.categoryId!},
        BudgetScopeType.multiCategory =>
          budgetCategoryIds[budget.id] ?? const <String>{},
        BudgetScopeType.uncategorized => const <String>{},
        BudgetScopeType.wholeAccount => const <String>{},
      };
      if (budget.scopeType == BudgetScopeType.multiCategory &&
          resolved.length < 2) {
        throw ValidationException(
          'A multi-category budget in this backup lists fewer than 2 '
          'categories (id "${budget.id}").',
        );
      }
      for (final categoryId in resolved) {
        if (!categoryIds.contains(categoryId)) {
          throw ValidationException(
            'A budget in this backup refers to a category that the backup '
            'does not contain (id "$categoryId").',
          );
        }
      }
    }
  }

  Future<int> _count(TableInfo<Table, dynamic> table) async {
    final total = countAll();
    final query = _database.selectOnly(table)..addColumns([total]);
    final row = await query.getSingle();
    return row.read(total) ?? 0;
  }
}

/// A backup that has been parsed and fully validated, ready to restore.
class ParsedBackup {
  const ParsedBackup({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.budgets,
    this.loans = const [],
    this.budgetCategoryIds = const {},
  });

  final List<FinancialAccountRow> accounts;
  final List<CategoryRow> categories;
  final List<TransactionRow> transactions;
  final List<BudgetRow> budgets;
  final List<LoanRow> loans;

  /// Each `MULTI_CATEGORY` budget's member categories, keyed by budget id
  /// (docs/adr/007-flexible-budget-scope.md). Every other scope type is
  /// absent from this map.
  final Map<String, Set<String>> budgetCategoryIds;

  BackupCounts get counts => BackupCounts(
    accounts: accounts.length,
    categories: categories.length,
    transactions: transactions.length,
    budgets: budgets.length,
    loans: loans.length,
  );
}
