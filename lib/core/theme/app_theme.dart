import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Central theme factory for FinOS.
///
/// Defines light and dark [ThemeData] instances using Material 3 and the
/// application's semantic color tokens (see docs/UI_DESIGN.md §27).
///
/// Material You: when the platform can supply a wallpaper-derived
/// [ColorScheme] (Android 12+, including One UI — Samsung's dynamic theming
/// reads from the same `WallpaperColors` API `DynamicColorBuilder` queries),
/// [light]/[dark] use it instead of the brand seed. Devices and platforms
/// without dynamic color (iOS, older Android) keep the fixed teal seed as a
/// deliberate, still-branded fallback.
abstract final class AppTheme {
  static const _seedColor = Color(0xFF006B5F);

  static ThemeData light([ColorScheme? dynamicScheme]) =>
      _build(Brightness.light, FinosColors.light, dynamicScheme);

  static ThemeData dark([ColorScheme? dynamicScheme]) =>
      _build(Brightness.dark, FinosColors.dark, dynamicScheme);

  static ThemeData _build(
    Brightness brightness,
    FinosColors finosColors,
    ColorScheme? dynamicScheme,
  ) {
    final scheme =
        dynamicScheme ??
        ColorScheme.fromSeed(seedColor: _seedColor, brightness: brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [finosColors],
    );
  }
}
