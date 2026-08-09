import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Central theme factory for FinOS.
///
/// Defines light and dark [ThemeData] instances using Material 3 and the
/// application's semantic color tokens (see docs/UI_DESIGN.md §27).
abstract final class AppTheme {
  static const _seedColor = Color(0xFF006B5F);

  static ThemeData light() => _build(Brightness.light, FinosColors.light);
  static ThemeData dark() => _build(Brightness.dark, FinosColors.dark);

  static ThemeData _build(Brightness brightness, FinosColors finosColors) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [finosColors],
    );
  }
}
