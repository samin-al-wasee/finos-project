import 'loan_direction.dart';

/// A partial, unsaved set of pre-fill values for [LoanFormScreen]'s create flow.
class LoanDraft {
  const LoanDraft({
    required this.direction,
    this.name = '',
    this.principalMinor,
    this.disbursementAccountId,
    this.startDate,
    this.description = '',
  });

  final LoanDirection direction;
  final String name;
  final int? principalMinor;
  final String? disbursementAccountId;

  /// Defaults to today when `null`, same as a blank new loan.
  final DateTime? startDate;
  final String description;
}

/// A partial, unsaved set of pre-fill values for [RepaymentDialog].
class RepaymentDraft {
  const RepaymentDraft({this.amountMinor, this.accountId, this.date});

  /// Defaults to the full outstanding amount when `null`, same as opening
  /// the dialog without a draft.
  final int? amountMinor;
  final String? accountId;

  /// Defaults to today when `null`.
  final DateTime? date;
}
