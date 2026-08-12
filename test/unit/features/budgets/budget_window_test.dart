import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [budgetWindow] — the calendar range a budget is measured over
/// (docs/DATA_MODEL.md §23).
///
/// The window is half-open `[from, to)`, so a transaction dated exactly on the
/// upper bound belongs to the next period and can never be counted twice.
void main() {
  group('monthly window', () {
    test('spans the reference calendar month', () {
      final window = budgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2026, 8, 10),
        startDate: DateTime(2026, 8, 10),
      );

      expect(window.from, DateTime(2026, 8, 1));
      expect(window.to, DateTime(2026, 9, 1));
      expect(window.lastDay, DateTime(2026, 8, 31));
    });

    test('ignores the day of month the budget was created on', () {
      // A budget created on the 27th still means "this calendar month".
      final window = budgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2026, 8, 3),
        startDate: DateTime(2026, 8, 27),
      );

      expect(window.from, DateTime(2026, 8, 1));
      expect(window.to, DateTime(2026, 9, 1));
    });

    test('rolls December over into January of the next year', () {
      final window = budgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2026, 12, 15),
        startDate: DateTime(2026, 12, 1),
      );

      expect(window.from, DateTime(2026, 12, 1));
      expect(window.to, DateTime(2027, 1, 1));
      expect(window.lastDay, DateTime(2026, 12, 31));
    });

    test('handles February in a leap year', () {
      final window = budgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2028, 2, 10),
        startDate: DateTime(2028, 2, 1),
      );

      expect(window.lastDay, DateTime(2028, 2, 29));
    });

    test('excludes the first day of the next month', () {
      final window = budgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2026, 8, 10),
        startDate: DateTime(2026, 8, 1),
      );

      expect(window.contains(DateTime(2026, 8, 1)), isTrue);
      expect(window.contains(DateTime(2026, 8, 31, 23, 59)), isTrue);
      expect(window.contains(DateTime(2026, 9, 1)), isFalse);
      expect(window.contains(DateTime(2026, 7, 31)), isFalse);
    });
  });

  group('weekly window', () {
    test('runs Monday through Sunday of the reference week', () {
      // 2026-08-12 is a Wednesday.
      final window = budgetWindow(
        BudgetPeriod.weekly,
        reference: DateTime(2026, 8, 12),
        startDate: DateTime(2026, 8, 12),
      );

      expect(window.from, DateTime(2026, 8, 10)); // Monday
      expect(window.to, DateTime(2026, 8, 17)); // next Monday
      expect(window.lastDay, DateTime(2026, 8, 16)); // Sunday
    });

    test('a Monday reference starts its own week', () {
      final window = budgetWindow(
        BudgetPeriod.weekly,
        reference: DateTime(2026, 8, 10),
        startDate: DateTime(2026, 8, 10),
      );

      expect(window.from, DateTime(2026, 8, 10));
    });

    test('a Sunday reference belongs to the week that began Monday', () {
      // 2026-08-16 is a Sunday.
      final window = budgetWindow(
        BudgetPeriod.weekly,
        reference: DateTime(2026, 8, 16),
        startDate: DateTime(2026, 8, 16),
      );

      expect(window.from, DateTime(2026, 8, 10));
      expect(window.to, DateTime(2026, 8, 17));
    });

    test('spans a month boundary when the week straddles one', () {
      // 2026-09-02 is a Wednesday; its week starts Monday 2026-08-31.
      final window = budgetWindow(
        BudgetPeriod.weekly,
        reference: DateTime(2026, 9, 2),
        startDate: DateTime(2026, 9, 1),
      );

      expect(window.from, DateTime(2026, 8, 31));
      expect(window.to, DateTime(2026, 9, 7));
    });
  });

  group('yearly window', () {
    test('spans the reference calendar year', () {
      final window = budgetWindow(
        BudgetPeriod.yearly,
        reference: DateTime(2026, 8, 10),
        startDate: DateTime(2026, 3, 5),
      );

      expect(window.from, DateTime(2026, 1, 1));
      expect(window.to, DateTime(2027, 1, 1));
      expect(window.lastDay, DateTime(2026, 12, 31));
    });
  });

  group('custom window', () {
    test('runs from the start date through the end date inclusive', () {
      final window = budgetWindow(
        BudgetPeriod.custom,
        reference: DateTime(2026, 8, 10),
        startDate: DateTime(2026, 8, 5),
        endDate: DateTime(2026, 8, 20),
      );

      expect(window.from, DateTime(2026, 8, 5));
      // Half-open upper bound is the midnight after the inclusive end date.
      expect(window.to, DateTime(2026, 8, 21));
      expect(window.lastDay, DateTime(2026, 8, 20));
      expect(window.contains(DateTime(2026, 8, 20, 18, 30)), isTrue);
      expect(window.contains(DateTime(2026, 8, 21)), isFalse);
    });

    test('ignores the reference date entirely', () {
      final window = budgetWindow(
        BudgetPeriod.custom,
        reference: DateTime(2030, 1, 1),
        startDate: DateTime(2026, 8, 5),
        endDate: DateTime(2026, 8, 20),
      );

      expect(window.from, DateTime(2026, 8, 5));
      expect(window.to, DateTime(2026, 8, 21));
    });

    test('a single-day window still contains that day', () {
      final window = budgetWindow(
        BudgetPeriod.custom,
        reference: DateTime(2026, 8, 10),
        startDate: DateTime(2026, 8, 10),
        endDate: DateTime(2026, 8, 10),
      );

      expect(window.contains(DateTime(2026, 8, 10, 12)), isTrue);
      expect(window.to, DateTime(2026, 8, 11));
    });

    test('throws without an end date', () {
      expect(
        () => budgetWindow(
          BudgetPeriod.custom,
          reference: DateTime(2026, 8, 10),
          startDate: DateTime(2026, 8, 5),
        ),
        throwsArgumentError,
      );
    });
  });

  group('date handling', () {
    test('discards the time component of the reference', () {
      final atMidnight = budgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2026, 8, 10),
        startDate: DateTime(2026, 8, 1),
      );
      final lateAtNight = budgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2026, 8, 10, 23, 59, 59),
        startDate: DateTime(2026, 8, 1),
      );

      expect(lateAtNight.from, atMidnight.from);
      expect(lateAtNight.to, atMidnight.to);
    });

    test('discards the time component of custom bounds', () {
      final window = budgetWindow(
        BudgetPeriod.custom,
        reference: DateTime(2026, 8, 10),
        startDate: DateTime(2026, 8, 5, 22, 15),
        endDate: DateTime(2026, 8, 20, 6, 45),
      );

      expect(window.from, DateTime(2026, 8, 5));
      expect(window.to, DateTime(2026, 8, 21));
    });

    test('dayStart normalises to local midnight', () {
      expect(dayStart(DateTime(2026, 8, 10, 17, 4, 3)), DateTime(2026, 8, 10));
    });
  });

  group('shiftedBudgetWindow', () {
    test('offset 0 matches budgetWindow for every recurring period', () {
      final reference = DateTime(2026, 8, 10);
      for (final period in [
        BudgetPeriod.weekly,
        BudgetPeriod.monthly,
        BudgetPeriod.yearly,
      ]) {
        final direct = budgetWindow(
          period,
          reference: reference,
          startDate: reference,
        );
        final shifted = shiftedBudgetWindow(
          period,
          reference: reference,
          offset: 0,
        );
        expect(shifted, direct, reason: '$period should agree at offset 0');
      }
    });

    test('monthly offset -1 is the previous calendar month', () {
      final window = shiftedBudgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2026, 8, 10),
        offset: -1,
      );
      expect(window, DateRange(from: DateTime(2026, 7), to: DateTime(2026, 8)));
    });

    test('monthly offset rolls under the year boundary from January', () {
      final window = shiftedBudgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2026, 1, 15),
        offset: -1,
      );
      expect(
        window,
        DateRange(from: DateTime(2025, 12), to: DateTime(2026, 1)),
      );
    });

    test('monthly offset -6 walks back across a year boundary', () {
      final window = shiftedBudgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2026, 2, 15),
        offset: -6,
      );
      expect(window, DateRange(from: DateTime(2025, 8), to: DateTime(2025, 9)));
    });

    test('weekly offset -1 is the previous Monday-Sunday week', () {
      final window = shiftedBudgetWindow(
        BudgetPeriod.weekly,
        reference: DateTime(2026, 8, 10), // a Monday
        offset: -1,
      );
      expect(
        window,
        DateRange(from: DateTime(2026, 8, 3), to: DateTime(2026, 8, 10)),
      );
    });

    test('yearly offset -1 is the previous calendar year', () {
      final window = shiftedBudgetWindow(
        BudgetPeriod.yearly,
        reference: DateTime(2026, 8, 10),
        offset: -1,
      );
      expect(window, DateRange(from: DateTime(2025), to: DateTime(2026)));
    });

    test('a positive offset looks forward instead of back', () {
      final window = shiftedBudgetWindow(
        BudgetPeriod.monthly,
        reference: DateTime(2026, 8, 10),
        offset: 1,
      );
      expect(
        window,
        DateRange(from: DateTime(2026, 9), to: DateTime(2026, 10)),
      );
    });

    test('custom has no repeating window, so it returns null', () {
      final window = shiftedBudgetWindow(
        BudgetPeriod.custom,
        reference: DateTime(2026, 8, 10),
        offset: -1,
      );
      expect(window, isNull);
    });
  });
}
