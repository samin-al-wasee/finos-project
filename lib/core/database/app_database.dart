import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

import '../../features/accounts/data/account_table.dart';
import '../../features/accounts/domain/account_status.dart';
import '../../features/accounts/domain/account_type.dart';
import '../../features/categories/data/built_in_categories.dart';
import '../../features/categories/data/category_table.dart';
import '../../features/categories/domain/category_origin.dart';
import '../../features/categories/domain/category_status.dart';
import '../../features/categories/domain/category_type.dart';

part 'app_database.g.dart';

/// The local application database (docs/ARCHITECTURE.md §12).
///
/// All Drift tables live in the features they belong to; this class aggregates
/// them and owns migration strategy and lifecycle.
@DriftDatabase(tables: [FinancialAccounts, Categories])
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
  int get schemaVersion => 2;

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
}
