import 'package:drift/drift.dart';

/// Which kind of fixed-term instrument this is
/// (docs/adr/009-investment-accounting.md).
///
/// This is purely descriptive — it never changes how contributions, payouts,
/// or maturity are computed, which depends only on [InvestmentContributionMode]
/// and [InvestmentPayoutFrequency]. It exists so the user can tell their
/// instruments apart (e.g. "5-year Sanchayapatra" vs. "1-year FDR") and so the
/// UI can show a sensible default icon/label.
enum InvestmentInstrumentType {
  /// Fixed Deposit Receipt — a lump-sum deposit at a fixed rate, maturing once.
  fdr,

  /// Deposit Pension Scheme — fixed recurring monthly deposits, maturing once
  /// at term end.
  dps,

  /// Bangladesh Sanchayapatra (national savings certificate) — a lump-sum
  /// deposit paying periodic profit, with principal returned at maturity.
  sanchayapatra,

  /// Any other fixed-term instrument not covered above.
  other,
}

/// Maps [InvestmentInstrumentType] to its canonical uppercase storage value
/// (`FDR`, `DPS`, `SANCHAYAPATRA`, `OTHER`).
class InvestmentInstrumentTypeConverter
    extends TypeConverter<InvestmentInstrumentType, String> {
  const InvestmentInstrumentTypeConverter();

  static const Map<InvestmentInstrumentType, String> _storage = {
    InvestmentInstrumentType.fdr: 'FDR',
    InvestmentInstrumentType.dps: 'DPS',
    InvestmentInstrumentType.sanchayapatra: 'SANCHAYAPATRA',
    InvestmentInstrumentType.other: 'OTHER',
  };

  @override
  InvestmentInstrumentType fromSql(String fromDb) {
    for (final entry in _storage.entries) {
      if (entry.value == fromDb) return entry.key;
    }
    throw ArgumentError(
      'Unknown InvestmentInstrumentType storage value: $fromDb',
    );
  }

  @override
  String toSql(InvestmentInstrumentType value) => _storage[value]!;
}

/// User-facing label for an [InvestmentInstrumentType].
String investmentInstrumentTypeLabel(InvestmentInstrumentType type) {
  switch (type) {
    case InvestmentInstrumentType.fdr:
      return 'FDR';
    case InvestmentInstrumentType.dps:
      return 'DPS';
    case InvestmentInstrumentType.sanchayapatra:
      return 'Sanchayapatra';
    case InvestmentInstrumentType.other:
      return 'Other';
  }
}
