import '../../../core/database/app_database.dart';
import 'theme_preference.dart';

/// Keys under which each preference is stored in the `preferences` table.
///
/// The table is key-value, so these strings are the schema. Never rename one
/// without a migration — a renamed key silently reverts the user's choice to its
/// default.
abstract final class SettingKeys {
  static const themePreference = 'theme_preference';
  static const defaultCurrency = 'default_currency';
}

/// A typed view over the stored preference rows.
///
/// The underlying table is heterogeneous key-value, which keeps new settings from
/// needing a schema migration each time. This class is the typed facade over it,
/// so nothing above the data layer handles raw strings.
///
/// Every field has a default, so a database with no preference rows at all — a
/// fresh install — yields a fully usable settings object.
class AppSettings {
  const AppSettings({
    this.themePreference = ThemePreference.system,
    this.defaultCurrency = defaultCurrencyFallback,
  });

  /// The currency used when no preference has been stored.
  ///
  /// Matches the column default on accounts, transactions, and budgets, so a
  /// user who never opens Settings sees consistent behaviour.
  static const defaultCurrencyFallback = 'BDT';

  /// Whether the app follows the system theme or is pinned to light/dark.
  final ThemePreference themePreference;

  /// ISO 4217 code preselected when creating a new account.
  final String defaultCurrency;

  /// Builds settings from raw preference rows, ignoring unknown keys.
  ///
  /// Unknown keys are tolerated rather than rejected so a database written by a
  /// newer version of the app still opens in an older one.
  factory AppSettings.fromRows(Iterable<PreferenceRow> rows) {
    final values = {for (final row in rows) row.key: row.value};
    return AppSettings(
      themePreference: themePreferenceFromStorage(
        values[SettingKeys.themePreference],
      ),
      defaultCurrency:
          values[SettingKeys.defaultCurrency] ?? defaultCurrencyFallback,
    );
  }

  AppSettings copyWith({
    ThemePreference? themePreference,
    String? defaultCurrency,
  }) {
    return AppSettings(
      themePreference: themePreference ?? this.themePreference,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themePreference == themePreference &&
      other.defaultCurrency == defaultCurrency;

  @override
  int get hashCode => Object.hash(themePreference, defaultCurrency);
}
