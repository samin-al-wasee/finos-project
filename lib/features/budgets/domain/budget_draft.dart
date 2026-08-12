import 'budget_period.dart';

/// A partial, unsaved set of pre-fill values for [BudgetFormScreen]'s create
/// flow.
class BudgetDraft {
  const BudgetDraft({
    this.categoryId,
    this.amountMinor,
    this.period = BudgetPeriod.monthly,
  });

  final String? categoryId;
  final int? amountMinor;
  final BudgetPeriod period;
}
