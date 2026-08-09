import '../constants/currencies.dart';

/// Parses a user-facing decimal string into integer minor units.
///
/// Examples:
/// ```dart
/// parseMinorUnits('50000');    // 5000000
/// parseMinorUnits('50,000');   // 5000000
/// parseMinorUnits('50000.50'); // 5000050
/// ```
///
/// Commas and whitespace are stripped. The string must represent a non-negative
/// finite decimal. Throws [FormatException] on invalid input.
int parseMinorUnits(String input, {int decimals = 2}) {
  final cleaned = input.replaceAll(RegExp(r'[,\s]'), '').trim();
  if (cleaned.isEmpty) throw const FormatException('Amount is empty');

  final value = double.tryParse(cleaned);
  if (value == null) throw FormatException('Invalid amount: $input');
  if (value < 0 || !value.isFinite) {
    throw const FormatException('Amount must be a non-negative finite number');
  }

  // Multiply by 10^decimals and round to avoid floating-point drift for values
  // like 0.1 that have no exact binary representation.
  return (value * _pow10(decimals)).round();
}

/// Formats integer minor units into a user-facing display string.
///
/// Examples:
/// ```dart
/// formatMinorUnits(5000000);              // '৳50,000.00'
/// formatMinorUnits(5000050);              // '৳50,000.50'
/// formatMinorUnits(-150000, symbol: '₹'); // '-₹1,500.00'
/// ```
String formatMinorUnits(
  int minorUnits, {
  int decimals = 2,
  String symbol = '৳',
}) {
  final isNeg = minorUnits < 0;
  final abs = minorUnits.abs();

  final major = abs ~/ _pow10(decimals);
  final fraction = abs % _pow10(decimals);

  final majorStr = _addCommas(major);
  final fractionStr = fraction.toString().padLeft(decimals, '0');

  final sign = isNeg ? '-' : '';
  return '$sign$symbol$majorStr.$fractionStr';
}

/// Returns the display symbol for a given ISO 4217 [code].
///
/// Falls back to the code itself when the currency is not in the V1 list.
String currencySymbol(String code) {
  for (final c in supportedCurrencies) {
    if (c.code == code) return c.symbol;
  }
  return code;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

int _pow10(int n) => n == 0 ? 1 : 10 * _pow10(n - 1);

/// Inserts comma thousands separators into a non-negative integer string.
String _addCommas(int value) {
  final str = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  return buffer.toString();
}
