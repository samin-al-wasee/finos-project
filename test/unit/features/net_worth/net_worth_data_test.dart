import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/investments/domain/investment_contribution_mode.dart';
import 'package:finos_app/features/investments/domain/investment_instrument_type.dart';
import 'package:finos_app/features/investments/domain/investment_payout_frequency.dart';
import 'package:finos_app/features/investments/domain/investment_progress.dart';
import 'package:finos_app/features/investments/domain/investment_status.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/loans/domain/loan_progress.dart';
import 'package:finos_app/features/loans/domain/loan_status.dart';
import 'package:finos_app/features/net_worth/domain/net_worth_data.dart';
import 'package:finos_app/features/recurring/domain/recurrence_frequency.dart';
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

  InvestmentProgress investment({
    required String id,
    int contributedMinor = 100000,
    int payoutReceivedMinor = 0,
    DateTime? latestPayoutDate,
    InvestmentStatus status = InvestmentStatus.active,
    DateTime? maturityDate,
    InvestmentPayoutFrequency payoutFrequency =
        const InvestmentPayoutFrequency.atMaturity(),
  }) => InvestmentProgress(
    investment: InvestmentRow(
      id: id,
      name: id,
      instrumentType: InvestmentInstrumentType.fdr,
      contributionMode: InvestmentContributionMode.lumpSum,
      amountMinor: contributedMinor,
      currency: 'BDT',
      sourceAccountId: 'bank',
      payoutAccountId: 'bank',
      startDate: timestamp,
      maturityDate: maturityDate ?? DateTime(2030, 1, 1),
      payoutFrequency: payoutFrequency,
      nextContributionDue: null,
      nextPayoutDue: null,
      status: status,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    contributedMinor: contributedMinor,
    payoutReceivedMinor: payoutReceivedMinor,
    latestPayoutDate: latestPayoutDate,
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

  group('investments', () {
    test('an active investment contributes contributed-minus-paid-out as an '
        'asset', () {
      final result = computeNetWorth(
        accounts: const [],
        balances: const {},
        loans: const [],
        investments: [investment(id: 'fdr', contributedMinor: 500000)],
      );

      expect(result.assets, [
        const NetWorthEntry(label: 'fdr', amountMinor: 500000),
      ]);
      expect(result.liabilities, isEmpty);
    });

    test('a Sanchayapatra mid-term with profit already withdrawn nets to '
        'exactly the original principal, not principal-minus-withdrawn-profit '
        '— a periodic payout is new profit already reflected in the payout '
        "account's own balance elsewhere in the snapshot, not a return of "
        'principal, so it must not reduce the locked value here (that would '
        'both double-count nothing and understate the position)', () {
      final result = computeNetWorth(
        accounts: const [],
        balances: const {},
        loans: const [],
        investments: [
          investment(
            id: 'sanchayapatra',
            contributedMinor: 1000000,
            // Three quarters of profit already paid out and sitting in
            // the payout account's own balance — dated well before
            // maturity, so the instrument is not settled.
            payoutReceivedMinor: 45000,
            latestPayoutDate: DateTime(2027, 10, 1),
            maturityDate: DateTime(2031, 1, 1),
            payoutFrequency: const InvestmentPayoutFrequency.periodic(
              RecurrenceFrequency.quarterly,
            ),
          ),
        ],
      );

      expect(result.assets, [
        const NetWorthEntry(
          label: 'sanchayapatra',
          amountMinor: 1000000, // unaffected by the withdrawn profit
        ),
      ]);
    });

    test('an archived investment is excluded entirely', () {
      final result = computeNetWorth(
        accounts: const [],
        balances: const {},
        loans: const [],
        investments: [
          investment(
            id: 'archived-fdr',
            contributedMinor: 500000,
            status: InvestmentStatus.archived,
          ),
        ],
      );

      expect(result.assets, isEmpty);
    });

    test('a settled investment (its maturity payout has been recorded) '
        'contributes nothing, even if the payout amount differs from the '
        'principal (interest included)', () {
      final result = computeNetWorth(
        accounts: const [],
        balances: const {},
        loans: const [],
        investments: [
          investment(
            id: 'settled-fdr',
            contributedMinor: 500000,
            payoutReceivedMinor: 550000, // principal + interest
            maturityDate: DateTime(2027, 1, 1),
            latestPayoutDate: DateTime(2027, 1, 1),
          ),
        ],
      );

      expect(result.assets, isEmpty);
    });

    test('a matured-but-unsettled investment still counts — the maturity '
        'payout has not happened yet, so the money has not moved', () {
      final result = computeNetWorth(
        accounts: const [],
        balances: const {},
        loans: const [],
        investments: [
          investment(
            id: 'matured-fdr',
            contributedMinor: 500000,
            maturityDate: DateTime(2020, 1, 1), // long past
          ),
        ],
      );

      expect(result.assets, [
        const NetWorthEntry(label: 'matured-fdr', amountMinor: 500000),
      ]);
    });

    test('mixed accounts, loans, and investments net out correctly', () {
      final result = computeNetWorth(
        accounts: [account(id: 'bank')],
        balances: {'bank': 100000},
        loans: [
          loan(
            id: 'john',
            direction: LoanDirection.lent,
            principalMinor: 20000,
          ),
        ],
        investments: [investment(id: 'fdr', contributedMinor: 30000)],
      );

      expect(result.assetsMinor, 100000 + 20000 + 30000);
      expect(result.liabilitiesMinor, 0);
      expect(result.netWorthMinor, 100000 + 20000 + 30000);
    });
  });
}
