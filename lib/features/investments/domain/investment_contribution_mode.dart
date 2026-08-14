import 'package:drift/drift.dart';

/// How principal is contributed to an investment
/// (docs/adr/009-investment-accounting.md).
enum InvestmentContributionMode {
  /// The full principal is deposited once, at creation (FDR, Sanchayapatra).
  lumpSum,

  /// A fixed amount is deposited every month for the instrument's term (DPS).
  /// The monthly amount is [InvestmentRow.amountMinor] — DPS has no other
  /// contribution frequency, so this mode is always monthly with no separate
  /// frequency field.
  recurring,
}

/// Maps [InvestmentContributionMode] to its canonical uppercase storage value
/// (`LUMP_SUM`, `RECURRING`).
class InvestmentContributionModeConverter
    extends TypeConverter<InvestmentContributionMode, String> {
  const InvestmentContributionModeConverter();

  static const Map<InvestmentContributionMode, String> _storage = {
    InvestmentContributionMode.lumpSum: 'LUMP_SUM',
    InvestmentContributionMode.recurring: 'RECURRING',
  };

  @override
  InvestmentContributionMode fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError(
      'Unknown InvestmentContributionMode storage value: $fromDb',
    );
  }

  @override
  String toSql(InvestmentContributionMode value) => _storage[value]!;
}

/// User-facing label for an [InvestmentContributionMode].
String investmentContributionModeLabel(InvestmentContributionMode mode) {
  switch (mode) {
    case InvestmentContributionMode.lumpSum:
      return 'Lump sum';
    case InvestmentContributionMode.recurring:
      return 'Recurring monthly deposit';
  }
}
