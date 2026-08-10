import '../../../core/constants/currencies.dart';
import '../data/settings_dao.dart';
import '../domain/app_settings.dart';
import '../domain/theme_preference.dart';

/// Application-service for user preferences (docs/UI_DESIGN.md §23).
///
/// Owns serialisation and validation so screens set typed values and never touch
/// raw strings or keys. Mutations are non-reactive — screens call these methods
/// and rely on [SettingsDao.watchAll] to refresh automatically.
class SettingsController {
  SettingsController(this._dao);

  final SettingsDao _dao;

  /// Stores the user's theme choice.
  Future<void> setThemePreference(ThemePreference preference) => _dao.put(
    SettingKeys.themePreference,
    themePreferenceToStorage(preference),
  );

  /// Stores the currency preselected when creating a new account.
  ///
  /// Throws [ArgumentError] for a code outside the V1 currency list — an
  /// unsupported code would have no symbol or decimal scale to format with
  /// (docs/DATA_MODEL.md §5).
  Future<void> setDefaultCurrency(String code) async {
    final supported = supportedCurrencies.any((c) => c.code == code);
    if (!supported) {
      throw ArgumentError('Unsupported currency code: $code');
    }
    await _dao.put(SettingKeys.defaultCurrency, code);
  }

  /// Reads the current preferences, falling back to defaults for unset keys.
  Future<AppSettings> read() async => AppSettings.fromRows(await _dao.getAll());
}
