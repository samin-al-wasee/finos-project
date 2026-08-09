import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../features/accounts/data/account_table.dart';
import '../../features/accounts/domain/account_status.dart';
import '../../features/accounts/domain/account_type.dart';

part 'app_database.g.dart';

/// The local application database (docs/ARCHITECTURE.md §12).
///
/// All Drift tables live in the features they belong to; this class aggregates
/// them and owns migration strategy and lifecycle.
@DriftDatabase(tables: [FinancialAccounts])
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Future migrations are added here.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
