import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/loans/domain/loan_progress.dart';
import 'package:finos_app/features/loans/domain/loan_status.dart';
import 'package:finos_app/features/net_worth/domain/net_worth_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [computeNetWorth] — a pure function over already-loaded
/// accounts/balances/loans, so no database is needed (docs/ROADMAP.md §9.1).
void main() {
  final timestamp = DateTime(2026, 8, 10);

  FinancialAccountRow account({
    required String id,
    AccountType type = AccountType.bank,
    AccountStatus status = AccountStatus.active,
  }) => FinancialAccountRow(
    id: id,
    name: id,
    type: type,
    currency: 'BDT',
    openingBalanceMinor: 0,
    createdAt: timestamp,
    updatedAt: timestamp,
    status: status,
  );

  LoanProgress loan({
    required String id,
    LoanDirection direction = LoanDirection.lent,
    int principalMinor = 20000,
    int repaidMinor = 0,
    LoanStatus status = LoanStatus.active,
  }) => LoanProgress(
    loan: LoanRow(
      id: id,
      type: direction,
      name: id,
      principalMinor: principalMinor,
      currency: 'BDT',
      startDate: timestamp,
      dueDate: null,
      description: '',
      disbursementAccountId: null,
      status: status,
      groupId: null,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    repaidMinor: repaidMinor,
    repaymentCount: 0,
  );

  test('a plain account contributes its balance as an asset', () {
    final result = computeNetWorth(
      accounts: [account(id: 'bank')],
      balances: {'bank': 50000},
      loans: const [],
    );

    expect(result.assets, [
      const NetWorthEntry(label: 'bank', amountMinor: 50000),
    ]);
    expect(result.liabilities, isEmpty);
    expect(result.netWorthMinor, 50000);
  });

  test(
    'an overdrawn non-credit account stays an asset entry, not a liability',
    () {
      final result = computeNetWorth(
        accounts: [account(id: 'bank')],
        balances: {'bank': -3000},
        loans: const [],
      );

      expect(result.assets, [
        const NetWorthEntry(label: 'bank', amountMinor: -3000),
      ]);
      expect(result.liabilities, isEmpty);
      expect(result.netWorthMinor, -3000);
    },
  );

  test('a credit card with debt contributes it as a liability', () {
    final result = computeNetWorth(
      accounts: [account(id: 'card', type: AccountType.creditCard)],
      balances: {'card': -8000},
      loans: const [],
    );

    expect(result.assets, isEmpty);
    expect(result.liabilities, [
      const NetWorthEntry(label: 'card', amountMinor: 8000),
    ]);
    expect(result.netWorthMinor, -8000);
  });

  test(
    'a credit card with a positive balance (credit, not debt) contributes nothing',
    () {
      final result = computeNetWorth(
        accounts: [account(id: 'card', type: AccountType.creditCard)],
        balances: {'card': 500},
        loans: const [],
      );

      expect(result.assets, isEmpty);
      expect(result.liabilities, isEmpty);
    },
  );

  test('an archived account is excluded entirely', () {
    final result = computeNetWorth(
      accounts: [account(id: 'closed', status: AccountStatus.archived)],
      balances: {'closed': 100000},
      loans: const [],
    );

    expect(result.assets, isEmpty);
    expect(result.liabilities, isEmpty);
  });

  test('a lent loan contributes its outstanding amount as an asset', () {
    final result = computeNetWorth(
      accounts: const [],
      balances: const {},
      loans: [
        loan(id: 'john', direction: LoanDirection.lent, principalMinor: 20000),
      ],
    );

    expect(result.assets, [
      const NetWorthEntry(label: 'john', amountMinor: 20000),
    ]);
    expect(result.liabilities, isEmpty);
  });

  test('a borrowed loan contributes its outstanding amount as a liability', () {
    final result = computeNetWorth(
      accounts: const [],
      balances: const {},
      loans: [
        loan(
          id: 'bank-loan',
          direction: LoanDirection.borrowed,
          principalMinor: 500000,
        ),
      ],
    );

    expect(result.liabilities, [
      const NetWorthEntry(label: 'bank-loan', amountMinor: 500000),
    ]);
    expect(result.assets, isEmpty);
  });

  test('a fully repaid loan is excluded', () {
    final result = computeNetWorth(
      accounts: const [],
      balances: const {},
      loans: [loan(id: 'paid-off', principalMinor: 20000, repaidMinor: 20000)],
    );

    expect(result.assets, isEmpty);
    expect(result.liabilities, isEmpty);
  });

  test('an archived loan is excluded even with outstanding balance', () {
    final result = computeNetWorth(
      accounts: const [],
      balances: const {},
      loans: [loan(id: 'archived', status: LoanStatus.archived)],
    );

    expect(result.assets, isEmpty);
    expect(result.liabilities, isEmpty);
  });

  test('mixed accounts and loans net out correctly', () {
    final result = computeNetWorth(
      accounts: [
        account(id: 'bank'),
        account(id: 'card', type: AccountType.creditCard),
      ],
      balances: {'bank': 100000, 'card': -20000},
      loans: [
        loan(id: 'john', direction: LoanDirection.lent, principalMinor: 20000),
        loan(
          id: 'bank-loan',
          direction: LoanDirection.borrowed,
          principalMinor: 50000,
        ),
      ],
    );

    expect(result.assetsMinor, 100000 + 20000);
    expect(result.liabilitiesMinor, 20000 + 50000);
    expect(result.netWorthMinor, (100000 + 20000) - (20000 + 50000));
  });
}
