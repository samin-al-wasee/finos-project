import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

import '../../features/accounts/data/account_table.dart';
import '../../features/accounts/data/credit_card_details_table.dart';
import '../../features/accounts/domain/account_status.dart';
import '../../features/accounts/domain/account_type.dart';
import '../../features/budgets/data/budget_category_table.dart';
import '../../features/budgets/data/budget_table.dart';
import '../../features/budgets/domain/budget_period.dart';
import '../../features/budgets/domain/budget_scope.dart';
import '../../features/budgets/domain/budget_status.dart';
import '../../features/categories/data/built_in_categories.dart';
import '../../features/categories/data/category_table.dart';
import '../../features/categories/domain/category_origin.dart';
import '../../features/categories/domain/category_status.dart';
import '../../features/categories/domain/category_type.dart';
import '../../features/investments/data/investment_table.dart';
import '../../features/investments/domain/investment_contribution_mode.dart';
import '../../features/investments/domain/investment_instrument_type.dart';
import '../../features/investments/domain/investment_payout_frequency.dart';
import '../../features/investments/domain/investment_status.dart';
import '../../features/loans/data/loan_table.dart';
import '../../features/loans/domain/loan_direction.dart';
import '../../features/loans/domain/loan_status.dart';
import '../../features/recurring/data/recurring_transaction_table.dart';
import '../../features/recurring/domain/recurrence_frequency.dart';
import '../../features/recurring/domain/recurring_status.dart';
import '../../features/settings/data/settings_table.dart';
import '../../features/templates/data/template_table.dart';
import '../../features/transactions/data/saved_query_table.dart';
import '../../features/transactions/data/transaction_table.dart';
import '../../features/transactions/domain/transaction_type.dart';

part 'app_database.g.dart';

/// The local application database (docs/ARCHITECTURE.md §12).
///
/// All Drift tables live in the features they belong to; this class aggregates
/// them and owns migration strategy and lifecycle.
@DriftDatabase(
  tables: [
    FinancialAccounts,
    Categories,
    Transactions,
    Budgets,
    Preferences,
    Loans,
    TransactionTemplates,
    RecurringTransactions,
    SavedQueries,
    CreditCardDetails,
    BudgetCategories,
    Investments,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the on-device database.
  AppDatabase.open() : this(driftDatabase(name: 'finos_app'));

  /// Creates a throwaway in-memory database for tests.
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  // ------------------------------------------------------------------
  // Schema
  // ------------------------------------------------------------------

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      debugPrint('[AppDatabase] onCreate — fresh database');
      await m.createAll();
      await _seedBuiltInCategories();
      debugPrint('[AppDatabase] onCreate — done');
    },
    onUpgrade: (m, from, to) async {
      debugPrint('[AppDatabase] onUpgrade $from → $to');
      if (from < 2) {
        // CREATE TABLE IF NOT EXISTS — safe even if the table partially exists.
        await m.createTable(categories);
        // Seed with insertOrIgnore so a partially-seeded table doesn't crash.
        await _seedBuiltInCategories();
      }
      if (from < 3) {
        // CREATE TABLE IF NOT EXISTS — safe even if the table partially exists.
        await m.createTable(transactions);
      }
      if (from < 4) {
        // CREATE TABLE IF NOT EXISTS — safe even if the table partially exists.
        await m.createTable(budgets);
      }
      if (from < 5) {
        // CREATE TABLE IF NOT EXISTS — safe even if the table partially exists.
        // Nothing is seeded: every preference falls back to a default when its
        // row is absent, so an empty table is a valid fresh state.
        await m.createTable(preferences);
      }
      if (from < 6) {
        // Loans first: transactions.loan_id references it.
        await m.createTable(loans);
        // Additive column, null for every existing row — no ordinary transaction
        // belongs to a loan (ADR-004).
        //
        // Checked rather than added blindly: when upgrading from before v3, the
        // step above created the transactions table from the *current* schema,
        // which already includes this column, and a second ALTER would fail with
        // "duplicate column name".
        await _addLoanIdColumnIfMissing();
      }
      if (from < 7) {
        // CREATE TABLE IF NOT EXISTS — safe even if the table partially exists.
        await m.createTable(transactionTemplates);
      }
      if (from < 8) {
        // CREATE TABLE IF NOT EXISTS — safe even if the table partially exists.
        await m.createTable(recurringTransactions);
      }
      if (from < 9) {
        // CREATE TABLE IF NOT EXISTS — safe even if the table partially exists.
        await m.createTable(savedQueries);
      }
      if (from < 10) {
        // CREATE TABLE IF NOT EXISTS — safe even if the table partially exists.
        await m.createTable(creditCardDetails);
      }
      if (from < 11) {
        // Additive column, null for every existing row — no loan is linked yet.
        await _addLoanGroupIdColumnIfMissing();
      }
      if (from < 12) {
        // Budgets: category_id becomes nullable (a MULTI_CATEGORY/
        // UNCATEGORIZED/WHOLE_ACCOUNT budget has no single category to store
        // there) and gains scope_type. SQLite has no ALTER COLUMN, so
        // relaxing an existing NOT NULL constraint needs a full table rebuild
        // rather than an additive ALTER TABLE. TableMigration performs that
        // rebuild with drift's own DDL, copying every matching-named column
        // across and applying scope_type's default for the one genuinely new
        // column, so every existing budget becomes SINGLE_CATEGORY with its
        // category_id untouched.
        //
        // rollover_enabled is listed as "new" here too, even though it is a
        // separate (v13) feature: TableMigration diffs against the *current*
        // Dart table definition, which already includes rollover_enabled, so
        // any column not listed here is assumed to already exist in the
        // pre-rebuild table and would otherwise fail to copy for a database
        // migrating from below v12 (which has neither column yet). Listing
        // both means one rebuild handles both additions; the from < 13 step
        // below's own idempotency check then finds the column already
        // present and skips its ALTER TABLE.
        //
        // TableMigration requires the table it rebuilds to already exist —
        // it copies rows out of it by name. A database that claims v4+ but
        // never actually got its budgets table (the interrupted-migration
        // scenario the v4 beforeOpen safety net exists for) has nothing to
        // copy from yet, so this step is skipped for it; the safety net
        // creates the table from the current schema afterwards, which
        // already includes scope_type, rollover_enabled, and a nullable
        // category_id.
        if (await _tableExists('budgets')) {
          await m.alterTable(
            TableMigration(
              budgets,
              newColumns: [budgets.scopeType, budgets.rolloverEnabled],
            ),
          );
        }
        // CREATE TABLE IF NOT EXISTS — safe even if the table partially exists.
        await m.createTable(budgetCategories);
      }
      if (from < 13) {
        // Plain additive column, no table rebuild — unlike v12, which had to
        // relax an existing NOT NULL constraint. Checked rather than added
        // blindly for the same reason as every other additive column here:
        // an upgrade from before v4 just created the budgets table from the
        // current schema, which already includes this column.
        await _addRolloverEnabledColumnIfMissing();
      }
      if (from < 14) {
        // Investments first: transactions.investment_id references it — same
        // ordering rule the v6 loans migration follows.
        await m.createTable(investments);
        // Additive column, null for every existing row — no ordinary
        // transaction belongs to an investment (docs/adr/009).
        //
        // Checked rather than added blindly for the same reason as
        // `_addLoanIdColumnIfMissing`: an upgrade from before v3 just created
        // the transactions table from the current schema, which already
        // includes this column.
        await _addInvestmentIdColumnIfMissing();
      }
      debugPrint('[AppDatabase] onUpgrade — done');
    },
    beforeOpen: (details) async {
      debugPrint(
        '[AppDatabase] beforeOpen — '
        'wasCreated=${details.wasCreated}, '
        'wasUpgrade=${details.hadUpgrade}, '
        'v${details.versionBefore ?? 0} → ${details.versionNow}',
      );
      await customStatement('PRAGMA foreign_keys = ON');

      // Safety net: if a v2 database opens with a missing or empty categories
      // table (e.g. from an interrupted migration or partial build), recreate
      // and re-seed so the app isn't stuck without categories.
      if (details.versionNow >= 2 && !details.wasCreated) {
        await _ensureCategoriesSeeded();
      }

      // Safety net: if a v3 database opens with a missing transactions table
      // (e.g. an interrupted migration that bumped user_version without
      // creating the table), recreate it so the app doesn't crash on queries.
      if (details.versionNow >= 3 && !details.wasCreated) {
        await _ensureTransactionsTable();
      }

      // Same safety net for the v4 budgets table.
      if (details.versionNow >= 4 && !details.wasCreated) {
        await _ensureBudgetsTable();
      }

      // Same safety net for the v5 preferences table.
      if (details.versionNow >= 5 && !details.wasCreated) {
        await _ensurePreferencesTable();
      }

      // Safety net for v6, which both added a table and altered an existing one.
      if (details.versionNow >= 6 && !details.wasCreated) {
        await _ensureLoansSchema();
      }

      // Same safety net for the v7 transaction templates table.
      if (details.versionNow >= 7 && !details.wasCreated) {
        await _ensureTemplatesTable();
      }

      // Same safety net for the v8 recurring transactions table.
      if (details.versionNow >= 8 && !details.wasCreated) {
        await _ensureRecurringTransactionsTable();
      }

      // Same safety net for the v9 saved queries table.
      if (details.versionNow >= 9 && !details.wasCreated) {
        await _ensureSavedQueriesTable();
      }

      // Same safety net for the v10 credit card details table.
      if (details.versionNow >= 10 && !details.wasCreated) {
        await _ensureCreditCardDetailsTable();
      }

      // Same safety net for the v11 loans.group_id column.
      if (details.versionNow >= 11 && !details.wasCreated) {
        await _addLoanGroupIdColumnIfMissing();
      }

      // Safety net for the v12 budget_categories table only. Deliberately no
      // net for a half-rebuilt budgets table: a TableMigration rebuild is a
      // multi-statement sequence (create-new, copy, drop-old, rename) with no
      // equally cheap "did this fully complete?" check, so that residual risk
      // is an accepted trade-off (docs/adr/007-flexible-budget-scope.md)
      // rather than one this safety net can paper over.
      if (details.versionNow >= 12 && !details.wasCreated) {
        await _ensureBudgetCategoriesTable();
      }

      // Same safety net for the v13 budgets.rollover_enabled column.
      if (details.versionNow >= 13 && !details.wasCreated) {
        await _addRolloverEnabledColumnIfMissing();
      }

      // Safety net for a v14 database missing part of the investments schema.
      // Same rationale as _ensureLoansSchema (v6): this version both created a
      // table and altered an existing one, so an interruption can leave
      // either half undone.
      if (details.versionNow >= 14 && !details.wasCreated) {
        await _ensureInvestmentsSchema();
      }
    },
  );

  /// Inserts built-in categories with [InsertMode.insertOrIgnore] so that
  /// re-seeding is always idempotent — duplicate PKs are silently skipped.
  Future<void> _seedBuiltInCategories() async {
    await batch(
      (b) => b.insertAll(
        categories,
        builtInCategories,
        mode: InsertMode.insertOrIgnore,
      ),
    );
  }

  /// Safety net for a v2 database whose categories table is missing or empty.
  ///
  /// Catches partial migrations (e.g. `user_version` was bumped but the table
  /// was never created, or the seed failed partway through). Uses a raw
  /// `CREATE TABLE IF NOT EXISTS` matching drift's generated schema exactly,
  /// then per-row typed inserts with [InsertMode.insertOrIgnore] (idempotent).
  Future<void> _ensureCategoriesSeeded() async {
    await customStatement('''CREATE TABLE IF NOT EXISTS "categories" (
        "id"          TEXT NOT NULL PRIMARY KEY,
        "name"        TEXT NOT NULL,
        "type"        TEXT NOT NULL,
        "origin"      TEXT NOT NULL DEFAULT 'USER',
        "icon"        TEXT NOT NULL DEFAULT 'label',
        "status"      TEXT NOT NULL DEFAULT 'ACTIVE',
        "created_at"  INTEGER NOT NULL DEFAULT
          (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        "updated_at"  INTEGER NOT NULL DEFAULT
          (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      )''');

    final count = await customSelect(
      'SELECT COUNT(*) AS c FROM categories',
    ).getSingleOrNull();
    if ((count?.read<int>('c') ?? 0) > 0) return;

    debugPrint(
      '[AppDatabase] categories table empty after upgrade — re-seeding',
    );
    for (final entry in builtInCategories) {
      await into(categories).insert(entry, mode: InsertMode.insertOrIgnore);
    }
    final after = await customSelect(
      'SELECT COUNT(*) AS c FROM categories',
    ).getSingleOrNull();
    debugPrint('[AppDatabase] re-seeded → ${after?.read<int>('c')} rows');
  }

  /// Safety net for a v3 database whose transactions table is missing.
  ///
  /// Catches interrupted migrations (e.g. `user_version` was bumped but the
  /// table was never created). Uses drift's own DDL via [Migrator.createTable]
  /// so the schema is always exactly what drift expects — no hand-maintained
  /// SQL to drift out of sync.
  Future<void> _ensureTransactionsTable() async {
    final migrator = Migrator(this);
    await migrator.createTable(transactions);
  }

  /// Safety net for a v4 database whose budgets table is missing.
  ///
  /// Same rationale as [_ensureTransactionsTable]: an interrupted migration can
  /// bump `user_version` without creating the table, which would otherwise crash
  /// the Budgets tab on every query.
  Future<void> _ensureBudgetsTable() async {
    final migrator = Migrator(this);
    await migrator.createTable(budgets);
  }

  /// Safety net for a v5 database whose preferences table is missing.
  ///
  /// Same rationale as [_ensureTransactionsTable]. This one matters at launch:
  /// the theme is read from preferences while the app builds, so a missing table
  /// would fail before any screen renders.
  Future<void> _ensurePreferencesTable() async {
    final migrator = Migrator(this);
    await migrator.createTable(preferences);
  }

  /// Safety net for a v6 database missing part of the loans schema.
  ///
  /// v6 is the first migration that both created a table and altered an existing
  /// one, so an interruption can leave either half undone. [Migrator.createTable]
  /// is `CREATE TABLE IF NOT EXISTS` and so is safe to repeat, but `ALTER TABLE
  /// ADD COLUMN` is not — the column is checked for first via `PRAGMA table_info`.
  /// The DDL still comes from drift's own definition, so there is no
  /// hand-maintained SQL to drift out of sync.
  Future<void> _ensureLoansSchema() async {
    final migrator = Migrator(this);
    await migrator.createTable(loans);
    await _addLoanIdColumnIfMissing();
  }

  /// Adds `transactions.loan_id` only when it is absent.
  ///
  /// `ALTER TABLE ADD COLUMN` is not idempotent, and there are two ways the
  /// column can already exist: the transactions table may have just been created
  /// from the current schema earlier in the same upgrade, or a previous run may
  /// have added it before being interrupted. The DDL still comes from drift's own
  /// definition, so there is no hand-maintained SQL to drift out of sync.
  Future<void> _addLoanIdColumnIfMissing() async {
    final columns = await customSelect('PRAGMA table_info(transactions)').get();

    // An empty result means the table does not exist at all. That happens when a
    // database claims v3+ but never got its transactions table: `onUpgrade` runs
    // before the `beforeOpen` net that recreates it, so there is nothing to alter
    // yet. Skipping is correct — the net creates the table from the current
    // schema, which already includes this column.
    if (columns.isEmpty) return;

    final hasLoanId = columns.any(
      (row) => row.read<String>('name') == 'loan_id',
    );
    if (hasLoanId) return;

    debugPrint('[AppDatabase] transactions.loan_id missing — adding');
    await Migrator(this).addColumn(transactions, transactions.loanId);
  }

  /// Safety net for a v7 database whose transaction templates table is
  /// missing.
  ///
  /// Same rationale as [_ensureTransactionsTable].
  Future<void> _ensureTemplatesTable() async {
    final migrator = Migrator(this);
    await migrator.createTable(transactionTemplates);
  }

  /// Safety net for a v8 database whose recurring transactions table is
  /// missing.
  ///
  /// Same rationale as [_ensureTransactionsTable].
  Future<void> _ensureRecurringTransactionsTable() async {
    final migrator = Migrator(this);
    await migrator.createTable(recurringTransactions);
  }

  /// Safety net for a v9 database whose saved queries table is missing.
  ///
  /// Same rationale as [_ensureTransactionsTable].
  Future<void> _ensureSavedQueriesTable() async {
    final migrator = Migrator(this);
    await migrator.createTable(savedQueries);
  }

  /// Safety net for a v10 database whose credit card details table is
  /// missing.
  ///
  /// Same rationale as [_ensureTransactionsTable].
  Future<void> _ensureCreditCardDetailsTable() async {
    final migrator = Migrator(this);
    await migrator.createTable(creditCardDetails);
  }

  /// Adds `loans.group_id` only when it is absent.
  ///
  /// Mirrors [_addLoanIdColumnIfMissing] exactly: `ALTER TABLE ADD COLUMN` is
  /// not idempotent, and the column could already exist either because the
  /// loans table was just created from the current schema earlier in the same
  /// upgrade, or because a previous run added it before being interrupted.
  /// The DDL still comes from drift's own definition, so there is no
  /// hand-maintained SQL to drift out of sync.
  Future<void> _addLoanGroupIdColumnIfMissing() async {
    final columns = await customSelect('PRAGMA table_info(loans)').get();

    // An empty result means the loans table itself is missing — the v6 safety
    // net handles recreating it (from the current schema, which already
    // includes this column), so there is nothing to alter yet.
    if (columns.isEmpty) return;

    final hasGroupId = columns.any(
      (row) => row.read<String>('name') == 'group_id',
    );
    if (hasGroupId) return;

    debugPrint('[AppDatabase] loans.group_id missing — adding');
    await Migrator(this).addColumn(loans, loans.groupId);
  }

  /// Safety net for a v12 database whose budget_categories table is missing.
  ///
  /// Same rationale as [_ensureTransactionsTable]. This is the only safety
  /// net v12 gets: the budgets table's own rebuild has no equivalent, cheap
  /// "is it whole?" check (docs/adr/007-flexible-budget-scope.md).
  Future<void> _ensureBudgetCategoriesTable() async {
    final migrator = Migrator(this);
    await migrator.createTable(budgetCategories);
  }

  /// Adds `budgets.rollover_enabled` only when it is absent.
  ///
  /// Mirrors [_addLoanGroupIdColumnIfMissing] exactly: `ALTER TABLE ADD
  /// COLUMN` is not idempotent, and the column could already exist either
  /// because the budgets table was just created from the current schema
  /// earlier in the same upgrade, or because a previous run added it before
  /// being interrupted. The DDL still comes from drift's own definition, so
  /// there is no hand-maintained SQL to drift out of sync.
  Future<void> _addRolloverEnabledColumnIfMissing() async {
    final columns = await customSelect('PRAGMA table_info(budgets)').get();

    // An empty result means the budgets table itself is missing — an earlier
    // safety net handles recreating it (from the current schema, which
    // already includes this column), so there is nothing to alter yet.
    if (columns.isEmpty) return;

    final hasRolloverEnabled = columns.any(
      (row) => row.read<String>('name') == 'rollover_enabled',
    );
    if (hasRolloverEnabled) return;

    debugPrint('[AppDatabase] budgets.rollover_enabled missing — adding');
    await Migrator(this).addColumn(budgets, budgets.rolloverEnabled);
  }

  /// Safety net for a v14 database missing part of the investments schema.
  ///
  /// Mirrors [_ensureLoansSchema] exactly: v14 both created a table and
  /// altered an existing one, so an interruption can leave either half
  /// undone. [Migrator.createTable] is `CREATE TABLE IF NOT EXISTS` and so is
  /// safe to repeat, but `ALTER TABLE ADD COLUMN` is not — the column is
  /// checked for first via `PRAGMA table_info`.
  Future<void> _ensureInvestmentsSchema() async {
    final migrator = Migrator(this);
    await migrator.createTable(investments);
    await _addInvestmentIdColumnIfMissing();
  }

  /// Adds `transactions.investment_id` only when it is absent.
  ///
  /// Mirrors [_addLoanIdColumnIfMissing] exactly: `ALTER TABLE ADD COLUMN` is
  /// not idempotent, and there are two ways the column can already exist: the
  /// transactions table may have just been created from the current schema
  /// earlier in the same upgrade, or a previous run may have added it before
  /// being interrupted.
  Future<void> _addInvestmentIdColumnIfMissing() async {
    final columns = await customSelect('PRAGMA table_info(transactions)').get();

    // An empty result means the table does not exist at all — same edge case
    // _addLoanIdColumnIfMissing documents. Skipping is correct: the v3 safety
    // net creates the table from the current schema, which already includes
    // this column.
    if (columns.isEmpty) return;

    final hasInvestmentId = columns.any(
      (row) => row.read<String>('name') == 'investment_id',
    );
    if (hasInvestmentId) return;

    debugPrint('[AppDatabase] transactions.investment_id missing — adding');
    await Migrator(this).addColumn(transactions, transactions.investmentId);
  }

  /// Whether a table named [name] currently exists.
  ///
  /// Used to guard the v12 `TableMigration` rebuild of `budgets`: that
  /// rebuild copies rows out of the existing table by name, so it must not
  /// run against a database that claims a version at or after the table was
  /// introduced but never actually got it (an interrupted migration — the
  /// same scenario each version's own `_ensure*Table` safety net exists
  /// for).
  Future<bool> _tableExists(String name) async {
    final rows = await customSelect('PRAGMA table_info($name)').get();
    return rows.isNotEmpty;
  }
}
