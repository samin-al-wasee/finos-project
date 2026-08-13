import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/domain/credit_card_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the credit-card statement-cycle math (docs/DATA_MODEL.md §60,
/// ADR-005) — [statementDateOnOrBefore], [nextStatementDateAfter], and the
/// derived getters on [CreditCardCycle].
void main() {
  group('statementDateOnOrBefore', () {
    test('returns this month\'s statement once it has closed', () {
      final date = statementDateOnOrBefore(DateTime(2026, 8, 10), 5);
      expect(date, DateTime(2026, 8, 5));
    });

    test('returns this month\'s statement on the statement day itself', () {
      final date = statementDateOnOrBefore(DateTime(2026, 8, 5), 5);
      expect(date, DateTime(2026, 8, 5));
    });

    test('falls back to last month before the statement closes', () {
      final date = statementDateOnOrBefore(DateTime(2026, 8, 3), 5);
      expect(date, DateTime(2026, 7, 5));
    });

    test('clamps day 31 to the 28th in a non-leap February', () {
      final date = statementDateOnOrBefore(DateTime(2026, 2, 28), 31);
      expect(date, DateTime(2026, 2, 28));
    });

    test('clamps day 31 to the 29th in a leap February', () {
      final date = statementDateOnOrBefore(DateTime(2028, 2, 29), 31);
      expect(date, DateTime(2028, 2, 29));
    });

    test('clamps day 30 to the 28th/29th in February', () {
      final date = statementDateOnOrBefore(DateTime(2026, 2, 28), 30);
      expect(date, DateTime(2026, 2, 28));
    });

    test('rolls back across a year boundary from January', () {
      final date = statementDateOnOrBefore(DateTime(2026, 1, 3), 20);
      expect(date, DateTime(2025, 12, 20));
    });

    test('discards the time component', () {
      final date = statementDateOnOrBefore(DateTime(2026, 8, 10, 23, 59), 5);
      expect(date, DateTime(2026, 8, 5));
    });
  });

  group('nextStatementDateAfter', () {
    test('advances one calendar month, same day', () {
      final date = nextStatementDateAfter(DateTime(2026, 8, 5), 5);
      expect(date, DateTime(2026, 9, 5));
    });

    test('rolls December over into January of the next year', () {
      final date = nextStatementDateAfter(DateTime(2026, 12, 20), 20);
      expect(date, DateTime(2027, 1, 20));
    });

    test('clamps into a shorter month', () {
      final date = nextStatementDateAfter(DateTime(2026, 1, 31), 31);
      expect(date, DateTime(2026, 2, 28));
    });
  });

  group('CreditCardCycle', () {
    CreditCardDetailsRow detailsWith({
      int creditLimitMinor = 10000000,
      int statementDay = 5,
      int paymentDueOffsetDays = 21,
    }) {
      final now = DateTime(2026, 8, 10);
      return CreditCardDetailsRow(
        id: 'card-1',
        accountId: 'acct-1',
        creditLimitMinor: creditLimitMinor,
        statementDay: statementDay,
        paymentDueOffsetDays: paymentDueOffsetDays,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('a negative balance is reported as positive outstanding debt', () {
      final cycle = CreditCardCycle(
        details: detailsWith(),
        currentBalanceMinor: -250000,
        previousStatementDate: DateTime(2026, 8, 5),
        previousStatementBalanceMinor: -250000,
      );

      expect(cycle.outstandingMinor, 250000);
      expect(cycle.availableCreditMinor, 10000000 - 250000);
    });

    test('a positive (credit) balance means nothing is owed', () {
      final cycle = CreditCardCycle(
        details: detailsWith(),
        currentBalanceMinor: 500,
        previousStatementDate: DateTime(2026, 8, 5),
        previousStatementBalanceMinor: 500,
      );

      expect(cycle.outstandingMinor, 0);
      expect(cycle.availableCreditMinor, 10000000);
    });

    test('available credit is clamped at zero once over the limit', () {
      final cycle = CreditCardCycle(
        details: detailsWith(creditLimitMinor: 100000),
        currentBalanceMinor: -250000,
        previousStatementDate: DateTime(2026, 8, 5),
        previousStatementBalanceMinor: -250000,
      );

      expect(cycle.outstandingMinor, 250000);
      expect(cycle.availableCreditMinor, 0);
    });

    test('previousStatementDebtMinor mirrors outstandingMinor\'s clamping', () {
      final cycle = CreditCardCycle(
        details: detailsWith(),
        currentBalanceMinor: -400000,
        previousStatementDate: DateTime(2026, 8, 5),
        previousStatementBalanceMinor: -300000,
      );

      expect(cycle.previousStatementDebtMinor, 300000);
    });

    test('paymentDueDate is the statement date plus the offset', () {
      final cycle = CreditCardCycle(
        details: detailsWith(paymentDueOffsetDays: 21),
        currentBalanceMinor: -300000,
        previousStatementDate: DateTime(2026, 8, 5),
        previousStatementBalanceMinor: -300000,
      );

      expect(cycle.paymentDueDate, DateTime(2026, 8, 26));
    });

    test('nextStatementDate is one cycle after the previous one', () {
      final cycle = CreditCardCycle(
        details: detailsWith(statementDay: 5),
        currentBalanceMinor: -300000,
        previousStatementDate: DateTime(2026, 8, 5),
        previousStatementBalanceMinor: -300000,
      );

      expect(cycle.nextStatementDate, DateTime(2026, 9, 5));
    });
  });
}
