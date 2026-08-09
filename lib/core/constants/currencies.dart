/// ISO 4217 currency metadata for the currencies supported in V1.
///
/// All V1 currencies use a decimal scale of 2 (i.e. 100 minor units per major
/// unit). The list is intentionally short; more currencies may be added later
/// when the data model supports per-currency decimal scale (DATA_MODEL.md §4–§5).
class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.name,
    this.decimals = 2,
  });

  /// ISO 4217 alphabetic code (e.g. `BDT`, `USD`).
  final String code;

  /// Display symbol (e.g. `৳`, `$`).
  final String symbol;

  /// Human-readable name (e.g. `Bangladeshi Taka`).
  final String name;

  /// Number of decimal (fraction) digits for the minor unit.
  final int decimals;
}

/// The fixed set of currencies available in V1.
const supportedCurrencies = [
  CurrencyInfo(code: 'BDT', symbol: '৳', name: 'Bangladeshi Taka'),
  CurrencyInfo(code: 'USD', symbol: r'$', name: 'US Dollar'),
  CurrencyInfo(code: 'INR', symbol: '₹', name: 'Indian Rupee'),
  CurrencyInfo(code: 'EUR', symbol: '€', name: 'Euro'),
  CurrencyInfo(code: 'GBP', symbol: '£', name: 'British Pound'),
];
