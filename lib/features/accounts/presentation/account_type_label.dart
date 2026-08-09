import 'package:flutter/material.dart';

import '../domain/account_type.dart';

/// User-facing label for an [AccountType].
///
/// Presentation-only text; the domain enum stays free of UI concerns.
String accountTypeLabel(AccountType type) {
  switch (type) {
    case AccountType.bank:
      return 'Bank';
    case AccountType.mfs:
      return 'Mobile Financial Service';
    case AccountType.creditCard:
      return 'Credit Card';
    case AccountType.debitCard:
      return 'Debit Card';
    case AccountType.cash:
      return 'Cash';
    case AccountType.other:
      return 'Other';
  }
}

/// Material icon associated with an [AccountType] for list tiles.
IconData accountTypeIcon(AccountType type) {
  switch (type) {
    case AccountType.bank:
      return Icons.account_balance;
    case AccountType.mfs:
      return Icons.smartphone;
    case AccountType.creditCard:
      return Icons.credit_card;
    case AccountType.debitCard:
      return Icons.credit_card_outlined;
    case AccountType.cash:
      return Icons.payments_outlined;
    case AccountType.other:
      return Icons.category_outlined;
  }
}
