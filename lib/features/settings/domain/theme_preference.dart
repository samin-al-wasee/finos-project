import 'package:flutter/material.dart';

/// The user's theme choice (docs/UI_DESIGN.md §23 — Appearance).
///
/// [system] follows the device setting, which is the default so a fresh install
/// matches the rest of the user's phone.
enum ThemePreference { system, light, dark }

/// Canonical uppercase storage value for each preference.
///
/// Settings are persisted as strings in a key-value table, so these are plain
/// parse/format helpers rather than a Drift [TypeConverter].
const Map<ThemePreference, String> _storage = {
  ThemePreference.system: 'SYSTEM',
  ThemePreference.light: 'LIGHT',
  ThemePreference.dark: 'DARK',
};

/// Serialises [preference] to its storage value.
String themePreferenceToStorage(ThemePreference preference) =>
    _storage[preference]!;

/// Parses a stored theme value, falling back to [ThemePreference.system].
///
/// Unrecognised and null values fall back rather than throwing: a settings row
/// written by a future version of the app must never make the app unlaunchable.
ThemePreference themePreferenceFromStorage(String? value) {
  if (value == null) return ThemePreference.system;
  for (final entry in _storage.entries) {
    if (entry.value == value) return entry.key;
  }
  return ThemePreference.system;
}

/// Maps the stored preference onto Flutter's [ThemeMode].
ThemeMode themeModeFor(ThemePreference preference) {
  switch (preference) {
    case ThemePreference.system:
      return ThemeMode.system;
    case ThemePreference.light:
      return ThemeMode.light;
    case ThemePreference.dark:
      return ThemeMode.dark;
  }
}
