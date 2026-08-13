import '../../../core/database/app_database.dart';
import 'list_view_mode.dart';
import 'theme_preference.dart';

/// Keys under which each preference is stored in the `preferences` table.
///
/// The table is key-value, so these strings are the schema. Never rename one
/// without a migration — a renamed key silently reverts the user's choice to its
/// default.
abstract final class SettingKeys {
  static const themePreference = 'theme_preference';
  static const defaultCurrency = 'default_currency';
  static const accountsViewMode = 'accounts_view_mode';
  static const loansViewMode = 'loans_view_mode';
  static const budgetsViewMode = 'budgets_view_mode';
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
    this.accountsViewMode = ListViewMode.list,
    this.loansViewMode = ListViewMode.list,
    this.budgetsViewMode = ListViewMode.list,
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

  /// Whether the Accounts tab remembers list or card view across restarts.
  final ListViewMode accountsViewMode;

  /// Whether the Loans tab remembers list or card view across restarts.
  final ListViewMode loansViewMode;

  /// Whether the Budgets tab remembers list or card view across restarts.
  final ListViewMode budgetsViewMode;

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
      accountsViewMode: listViewModeFromStorage(
        values[SettingKeys.accountsViewMode],
      ),
      loansViewMode: listViewModeFromStorage(values[SettingKeys.loansViewMode]),
      budgetsViewMode: listViewModeFromStorage(
        values[SettingKeys.budgetsViewMode],
      ),
    );
  }

  AppSettings copyWith({
    ThemePreference? themePreference,
    String? defaultCurrency,
    ListViewMode? accountsViewMode,
    ListViewMode? loansViewMode,
    ListViewMode? budgetsViewMode,
  }) {
    return AppSettings(
      themePreference: themePreference ?? this.themePreference,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      accountsViewMode: accountsViewMode ?? this.accountsViewMode,
      loansViewMode: loansViewMode ?? this.loansViewMode,
      budgetsViewMode: budgetsViewMode ?? this.budgetsViewMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themePreference == themePreference &&
      other.defaultCurrency == defaultCurrency &&
      other.accountsViewMode == accountsViewMode &&
      other.loansViewMode == loansViewMode &&
      other.budgetsViewMode == budgetsViewMode;

  @override
  int get hashCode => Object.hash(
    themePreference,
    defaultCurrency,
    accountsViewMode,
    loansViewMode,
    budgetsViewMode,
  );
}
