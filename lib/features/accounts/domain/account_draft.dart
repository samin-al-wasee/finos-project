import 'account_type.dart';

/// A partial, unsaved set of pre-fill values for [AccountFormScreen]'s create
/// flow.
class AccountDraft {
  const AccountDraft({
    this.name = '',
    this.type = AccountType.bank,
    this.openingBalanceMinor,
  });

  final String name;
  final AccountType type;
  final int? openingBalanceMinor;
}
