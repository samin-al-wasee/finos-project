import 'package:flutter/material.dart';

/// Semantic color tokens specific to FinOS.
///
/// Covers financial and status colors not already represented by the standard
/// Material [ColorScheme]. See docs/UI_DESIGN.md §25–§26.
@immutable
class FinosColors extends ThemeExtension<FinosColors> {
  const FinosColors({
    required this.income,
    required this.expense,
    required this.transfer,
    required this.warning,
    required this.error,
    required this.success,
    required this.mutedText,
    required this.border,
  });

  final Color income;
  final Color expense;
  final Color transfer;
  final Color warning;
  final Color error;
  final Color success;
  final Color mutedText;
  final Color border;

  // ---------------------------------------------------------------
  // Preset palettes
  // ---------------------------------------------------------------

  static const light = FinosColors(
    income: Color(0xFF1B7F3B),
    expense: Color(0xFFC62828),
    transfer: Color(0xFF1565C0),
    warning: Color(0xFFF9A825),
    error: Color(0xFFBA1A1A),
    success: Color(0xFF2E7D32),
    mutedText: Color(0xFF6B7280),
    border: Color(0xFFE5E7EB),
  );

  static const dark = FinosColors(
    income: Color(0xFF7ADB8A),
    expense: Color(0xFFFF8A80),
    transfer: Color(0xFF8FC7FF),
    warning: Color(0xFFFFD54F),
    error: Color(0xFFFFB4AB),
    success: Color(0xFF81C784),
    mutedText: Color(0xFF9CA3AF),
    border: Color(0xFF374151),
  );

  // ---------------------------------------------------------------
  // ThemeExtension boilerplate
  // ---------------------------------------------------------------

  @override
  FinosColors copyWith({
    Color? income,
    Color? expense,
    Color? transfer,
    Color? warning,
    Color? error,
    Color? success,
    Color? mutedText,
    Color? border,
  }) {
    return FinosColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      transfer: transfer ?? this.transfer,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      success: success ?? this.success,
      mutedText: mutedText ?? this.mutedText,
      border: border ?? this.border,
    );
  }

  @override
  FinosColors lerp(FinosColors? other, double t) {
    if (other is! FinosColors) return this;
    return FinosColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}
