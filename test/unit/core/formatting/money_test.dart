import 'package:finos_app/core/constants/currencies.dart';
import 'package:finos_app/core/formatting/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMinorUnits', () {
    test('parses an integer string', () {
      expect(parseMinorUnits('50000'), 5000000);
    });

    test('parses a string with commas', () {
      expect(parseMinorUnits('50,000'), 5000000);
    });

    test('parses a decimal string', () {
      expect(parseMinorUnits('50000.50'), 5000050);
    });

    test('parses a string with commas and decimals', () {
      expect(parseMinorUnits('1,250,000.75'), 125000075);
    });

    test('parses zero', () {
      expect(parseMinorUnits('0'), 0);
      expect(parseMinorUnits('0.00'), 0);
    });

    test('throws on empty string', () {
      expect(() => parseMinorUnits(''), throwsFormatException);
    });

    test('throws on non-numeric input', () {
      expect(() => parseMinorUnits('abc'), throwsFormatException);
    });

    test('throws on negative input', () {
      expect(() => parseMinorUnits('-100'), throwsFormatException);
    });

    test('accepts a trailing decimal point (treated as .0)', () {
      expect(parseMinorUnits('100.'), 10000);
    });
  });

  group('formatMinorUnits', () {
    test('formats a round amount with BDT symbol', () {
      expect(formatMinorUnits(5000000), '৳50,000.00');
    });

    test('formats an amount with fractional part', () {
      expect(formatMinorUnits(5000050), '৳50,000.50');
    });

    test('formats zero', () {
      expect(formatMinorUnits(0), '৳0.00');
    });

    test('formats a small amount', () {
      expect(formatMinorUnits(850), '৳8.50');
    });

    test('formats a large amount', () {
      expect(formatMinorUnits(125000000), '৳1,250,000.00');
    });

    test('formats with custom symbol', () {
      expect(formatMinorUnits(5000000, symbol: r'$'), r'$50,000.00');
    });

    test('formats negative amounts', () {
      expect(formatMinorUnits(-5000000), '-৳50,000.00');
    });
  });

  group('currencySymbol', () {
    test('returns the correct symbol for BDT', () {
      expect(currencySymbol('BDT'), '৳');
    });

    test('returns the correct symbol for USD', () {
      expect(currencySymbol('USD'), r'$');
    });

    test('falls back to the code for unknown currencies', () {
      expect(currencySymbol('XYZ'), 'XYZ');
    });
  });

  group('supportedCurrencies', () {
    test('contains 5 entries', () {
      expect(supportedCurrencies.length, 5);
    });

    test('all have 2 decimal places', () {
      for (final c in supportedCurrencies) {
        expect(c.decimals, 2);
      }
    });

    test('BDT is the first entry', () {
      expect(supportedCurrencies.first.code, 'BDT');
    });
  });
}
