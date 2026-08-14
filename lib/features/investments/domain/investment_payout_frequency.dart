import 'package:drift/drift.dart';

import '../../recurring/domain/recurrence_frequency.dart';

/// How often an investment pays out profit before maturity
/// (docs/adr/009-investment-accounting.md).
///
/// Wraps [RecurrenceFrequency] rather than adding a fifth value to it:
/// "no periodic payout, only at maturity" is the *absence* of a recurrence,
/// not a recurrence itself, and every other consumer of [RecurrenceFrequency]
/// (Recurring Transactions, Templates) would otherwise have to handle a case
/// that means something different in their context. Only
/// [RecurrenceFrequency.monthly], [RecurrenceFrequency.quarterly], and
/// [RecurrenceFrequency.yearly] are meaningful payout frequencies here — daily
/// and weekly profit payouts don't occur for these instruments, so the create
/// form only offers those three plus [atMaturity].
class InvestmentPayoutFrequency {
  const InvestmentPayoutFrequency.atMaturity() : periodic = null;

  const InvestmentPayoutFrequency.periodic(RecurrenceFrequency frequency)
    : periodic = frequency;

  /// `null` means "no periodic payout — everything happens at maturity."
  final RecurrenceFrequency? periodic;

  bool get isAtMaturity => periodic == null;

  @override
  bool operator ==(Object other) =>
      other is InvestmentPayoutFrequency && other.periodic == periodic;

  @override
  int get hashCode => periodic.hashCode;
}

/// Maps [InvestmentPayoutFrequency] to its canonical storage value: the
/// underlying [RecurrenceFrequency]'s storage string for the periodic case, or
/// the sentinel `AT_MATURITY`.
class InvestmentPayoutFrequencyConverter
    extends TypeConverter<InvestmentPayoutFrequency, String> {
  const InvestmentPayoutFrequencyConverter();

  static const _atMaturityStorage = 'AT_MATURITY';
  static const _frequencyConverter = RecurrenceFrequencyConverter();

  @override
  InvestmentPayoutFrequency fromSql(String fromDb) {
    if (fromDb == _atMaturityStorage) {
      return const InvestmentPayoutFrequency.atMaturity();
    }
    return InvestmentPayoutFrequency.periodic(
      _frequencyConverter.fromSql(fromDb),
    );
  }

  @override
  String toSql(InvestmentPayoutFrequency value) {
    final periodic = value.periodic;
    return periodic == null
        ? _atMaturityStorage
        : _frequencyConverter.toSql(periodic);
  }
}

/// User-facing label for an [InvestmentPayoutFrequency].
String investmentPayoutFrequencyLabel(InvestmentPayoutFrequency frequency) {
  final periodic = frequency.periodic;
  if (periodic == null) return 'At maturity';
  return recurrenceFrequencyLabel(periodic);
}
