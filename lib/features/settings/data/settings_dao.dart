import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'settings_table.dart';

part 'settings_dao.g.dart';

/// Data-access object for user preferences.
///
/// Preferences are read as a whole rather than one key at a time: there are only
/// a handful, the UI shows them together, and a single stream keeps every
/// consumer (the theme, the account form) in sync from one query.
@DriftAccessor(tables: [Preferences])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  /// Streams every stored preference row.
  Stream<List<PreferenceRow>> watchAll() => select(preferences).watch();

  /// One-shot fetch of every stored preference row.
  Future<List<PreferenceRow>> getAll() => select(preferences).get();

  /// Reads a single raw value, or `null` when the key has never been set.
  Future<String?> getValue(String key) async {
    final row = await (select(
      preferences,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// Writes [value] under [key], replacing any previous value.
  ///
  /// Uses an upsert so callers never have to know whether the preference has
  /// been set before; a setting has exactly one row or none.
  Future<void> put(String key, String value) async {
    await into(preferences).insertOnConflictUpdate(
      PreferencesCompanion.insert(
        key: key,
        value: value,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
