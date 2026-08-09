import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
      await m.createAll();
      await _seedBuiltInCategories();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(categories);
        await _seedBuiltInCategories();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Inserts the built-in categories so every install starts with a usable set.
  Future<void> _seedBuiltInCategories() async {
    await batch((b) => b.insertAll(categories, builtInCategories));
  }
}
