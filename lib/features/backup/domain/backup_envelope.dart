/// The backup file format (docs/DATA_MODEL.md §48).
///
/// A backup is a single JSON object: a small header identifying the format,
/// followed by one array per financial table.
///
/// ```json
/// {
///   "backup_version": 1,
///   "app_schema_version": 5,
///   "exported_at": "2026-08-10T14:32:00.000",
///   "accounts": [],
///   "categories": [],
///   "transactions": [],
///   "budgets": []
/// }
/// ```
abstract final class BackupFormat {
  /// Version of the *envelope* format written by this app.
  ///
  /// Bump this only when the shape of the file changes in a way an older
  /// importer could not read. It is independent of the database schema version,
  /// which is recorded separately so a future importer can tell which schema
  /// produced the data.
  static const version = 1;

  /// Envelope versions this build can import.
  ///
  /// A backup from a newer version is refused with a readable message rather
  /// than parsed on a guess — a half-understood restore is worse than none.
  static const supportedVersions = {1};

  // Header keys.
  static const versionKey = 'backup_version';
  static const schemaVersionKey = 'app_schema_version';
  static const exportedAtKey = 'exported_at';

  // Table keys, in dependency order: parents before the rows that reference
  // them, which is also a safe insert order on restore.
  static const accountsKey = 'accounts';
  static const categoriesKey = 'categories';
  static const transactionsKey = 'transactions';
  static const budgetsKey = 'budgets';

  /// Every table a backup carries.
  static const tableKeys = [
    accountsKey,
    categoriesKey,
    transactionsKey,
    budgetsKey,
  ];

  /// Suggested file name for an export, e.g. `finos-backup-2026-08-10.json`.
  ///
  /// Dated rather than timestamped so repeated same-day exports overwrite in the
  /// user's file manager instead of accumulating.
  static String fileNameFor(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'finos-backup-${date.year}-$month-$day.json';
  }
}

/// What a restore is about to do, or has just done.
///
/// Used to warn before replacing data and to confirm afterwards, so the user
/// always sees the size of the change in records rather than a bare "done".
class BackupCounts {
  const BackupCounts({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.budgets,
  });

  const BackupCounts.empty()
    : accounts = 0,
      categories = 0,
      transactions = 0,
      budgets = 0;

  final int accounts;
  final int categories;
  final int transactions;
  final int budgets;

  int get total => accounts + categories + transactions + budgets;

  bool get isEmpty => total == 0;

  @override
  bool operator ==(Object other) =>
      other is BackupCounts &&
      other.accounts == accounts &&
      other.categories == categories &&
      other.transactions == transactions &&
      other.budgets == budgets;

  @override
  int get hashCode => Object.hash(accounts, categories, transactions, budgets);

  @override
  String toString() =>
      'BackupCounts(accounts: $accounts, categories: $categories, '
      'transactions: $transactions, budgets: $budgets)';
}
