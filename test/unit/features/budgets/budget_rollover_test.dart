import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/budgets/domain/budget_rollover.dart';
import 'package:finos_app/features/budgets/domain/budget_scope.dart';
import 'package:finos_app/features/budgets/domain/budget_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [rolloverCarryInMinor] — the derived-at-read-time carry-in
/// calculation (docs/adr/008-budget-rollover.md).
///
/// Uses a fake, window-only [SpendLookup] keyed by the window's `from` date,
/// so every test is pure and needs no database. The generalisation to a
/// window-only signature (rather than one keyed by `categoryId`) is what lets
/// this same function work for every `BudgetScope` — the fakes below never
/// reference a category at all.
void main() {
  final timestamp = DateTime(2026, 8, 10);
  final reference = DateTime(2026, 8, 10); // a Monday, well inside August

  BudgetRow budgetWith({
    required int amountMinor,
    required BudgetPeriod period,
    required DateTime startDate,
    required bool rolloverEnabled,
  }) {
    return BudgetRow(
      id: 'budget-1',
      categoryId: null,
      scopeType: BudgetScopeType.wholeAccount,
      amountMinor: amountMinor,
      currency: 'BDT',
      period: period,
      startDate: startDate,
      endDate: null,
      status: BudgetStatus.active,
      createdAt: timestamp,
      updatedAt: timestamp,
      rolloverEnabled: rolloverEnabled,
    );
  }

  /// A [SpendLookup] that reports a fixed amount for every window,
  /// regardless of which one is asked for.
  SpendLookup constantSpend(int amountMinor) {
    return (from, to) async => amountMinor;
  }

  /// A [SpendLookup] driven by a map keyed on the window's `from` date, so a
  /// test can give each trailing period its own spend figure. Any window not
  /// present in [byFrom] reports zero spend.
  SpendLookup spendByWindowStart(Map<DateTime, int> byFrom) {
    return (from, to) async => byFrom[from] ?? 0;
  }

  group('off by default / inapplicable', () {
    test('rolloverEnabled: false returns 0 regardless of spend', () async {
      final budget = budgetWith(
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
        startDate: DateTime(2020, 1, 1),
        rolloverEnabled: false,
      );

      final carry = await rolloverCarryInMinor(
        budget: budget,
        reference: reference,
        // Reports zero spend every period, which would otherwise accumulate
        // a large surplus — proving the flag alone gates the whole
        // calculation.
        spentBetween: constantSpend(0),
      );

      expect(carry, 0);
    });

    test('a custom period returns 0 even with rolloverEnabled: true', () async {
      // Defensive at the domain layer: the controller/UI already reject this
      // combination, but the domain function must not compute a nonsense
      // carry if it is ever called with it anyway.
      final budget = budgetWith(
        amountMinor: 1000000,
        period: BudgetPeriod.custom,
        startDate: DateTime(2020, 1, 1),
        rolloverEnabled: true,
      );

      final carry = await rolloverCarryInMinor(
        budget: budget,
        reference: reference,
        spentBetween: constantSpend(0),
      );

      expect(carry, 0);
    });
  });

  group('simple carry', () {
    test('an under-spent previous period carries its surplus in full', () async {
      // start_date pinned to last month's own window start, so offset -1 is
      // the only eligible period — isolating the arithmetic under test from
      // the lookback walk's other 5 slots.
      final lastMonth = shiftedBudgetWindow(
        BudgetPeriod.monthly,
        reference: reference,
        offset: -1,
      )!;
      final budget = budgetWith(
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
        startDate: lastMonth.from,
        rolloverEnabled: true,
      );

      // Limit 10,000; last month spent only 6,000 → 4,000 unspent carries in.
      final carry = await rolloverCarryInMinor(
        budget: budget,
        reference: reference,
        spentBetween: spendByWindowStart({lastMonth.from: 600000}),
      );

      expect(carry, 400000);
    });
  });

  group('multi-period accumulation', () {
    test(
      'three consecutive under-spent periods compound the running sum',
      () async {
        // start_date pinned to offset -3's window start, so only -3, -2, -1
        // are eligible.
        final monthMinus3 = shiftedBudgetWindow(
          BudgetPeriod.monthly,
          reference: reference,
          offset: -3,
        )!;
        final budget = budgetWith(
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
          startDate: monthMinus3.from,
          rolloverEnabled: true,
        );

        // Limit 10,000/period. Three trailing months each spend 7,000, each
        // adding 3,000 (plus whatever already carried) to the next period's
        // effective limit:
        //   period -3: limit 10,000, spend 7,000 → remainder  3,000
        //   period -2: limit 13,000, spend 7,000 → remainder  6,000
        //   period -1: limit 16,000, spend 7,000 → remainder  9,000
        // carry into the current period is 9,000.
        final windows = {
          for (final offset in [-3, -2, -1])
            shiftedBudgetWindow(
              BudgetPeriod.monthly,
              reference: reference,
              offset: offset,
            )!.from: 700000,
        };

        final carry = await rolloverCarryInMinor(
          budget: budget,
          reference: reference,
          spentBetween: spendByWindowStart(windows),
        );

        expect(carry, 900000);
      },
    );
  });

  group('deficit case', () {
    test('an overspent period carries a negative deficit forward', () async {
      final lastMonth = shiftedBudgetWindow(
        BudgetPeriod.monthly,
        reference: reference,
        offset: -1,
      )!;
      final budget = budgetWith(
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
        startDate: lastMonth.from,
        rolloverEnabled: true,
      );

      // Limit 10,000; last month spent 13,000 → carry is -3,000.
      final carry = await rolloverCarryInMinor(
        budget: budget,
        reference: reference,
        spentBetween: spendByWindowStart({lastMonth.from: 1300000}),
      );

      expect(carry, -300000);
    });

    test('a following under-spent period nets the deficit down', () async {
      final monthMinus2 = shiftedBudgetWindow(
        BudgetPeriod.monthly,
        reference: reference,
        offset: -2,
      )!;
      final monthMinus1 = shiftedBudgetWindow(
        BudgetPeriod.monthly,
        reference: reference,
        offset: -1,
      )!;
      final budget = budgetWith(
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
        startDate: monthMinus2.from,
        rolloverEnabled: true,
      );

      // period -2: limit 10,000, spend 13,000 → remainder -3,000
      // period -1: limit 10,000 + (-3,000) = 7,000, spend 5,000 → remainder 2,000
      // carry into the current period is 2,000.
      final carry = await rolloverCarryInMinor(
        budget: budget,
        reference: reference,
        spentBetween: spendByWindowStart({
          monthMinus2.from: 1300000,
          monthMinus1.from: 500000,
        }),
      );

      expect(carry, 200000);
    });
  });

  group('start date inside the lookback window', () {
    test('periods before start_date are excluded from the walk', () async {
      // The budget only started 2 months ago, so offsets -3..-6 must not be
      // consulted at all — reported via a spend lookup that throws if asked
      // about a too-old window.
      final startDate = shiftedBudgetWindow(
        BudgetPeriod.monthly,
        reference: reference,
        offset: -2,
      )!.from;
      final budget = budgetWith(
        amountMinor: 1000000,
        period: BudgetPeriod.monthly,
        startDate: startDate,
        rolloverEnabled: true,
      );

      final queried = <DateTime>[];
      final carry = await rolloverCarryInMinor(
        budget: budget,
        reference: reference,
        spentBetween: (from, to) async {
          queried.add(from);
          return 600000; // under-spent by 4,000 relative to the 10,000 limit
        },
      );

      // Only offsets -2 and -1 postdate start_date, so exactly two periods
      // are queried and compound: 10,000+4,000 = 14,000 limit next,
      // spend 6,000 → remainder 8,000; net carry-in is 8,000.
      expect(queried, hasLength(2));
      expect(carry, 800000);
    });
  });

  group('lookback cap', () {
    test(
      'a large deficit placed outside the cap (offset -7) does not affect '
      "today's carry",
      () async {
        // A budget running long enough that offset -7 exists and would carry
        // a huge deficit forward if it were consulted; the cap must stop the
        // walk at -6.
        final budget = budgetWith(
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2000, 1, 1),
          rolloverEnabled: true,
        );
        final offsetMinus7 = shiftedBudgetWindow(
          BudgetPeriod.monthly,
          reference: reference,
          offset: -7,
        )!;

        final carry = await rolloverCarryInMinor(
          budget: budget,
          reference: reference,
          spentBetween: spendByWindowStart({
            // A catastrophic overspend at offset -7, which must be ignored.
            offsetMinus7.from: 999999999,
          }),
        );

        // Every consulted period (-6..-1) reports zero spend via the map's
        // default, so each contributes its own 10,000 surplus: 6 * 10,000.
        expect(carry, 6000000);
      },
    );

    test(
      'exactly rolloverLookbackLimit periods vs one more confirms the cutoff',
      () async {
        final budget = budgetWith(
          amountMinor: 1000000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2000, 1, 1),
          rolloverEnabled: true,
        );

        final queriedAtLimit = <DateTime>[];
        final carryAtLimit = await rolloverCarryInMinor(
          budget: budget,
          reference: reference,
          spentBetween: (from, to) async {
            queriedAtLimit.add(from);
            return 0;
          },
        );

        expect(queriedAtLimit, hasLength(rolloverLookbackLimit));
        expect(carryAtLimit, rolloverLookbackLimit * 1000000);

        // Confirm the exact boundary: offset -(limit + 1) is never queried.
        final oneBeyond = shiftedBudgetWindow(
          BudgetPeriod.monthly,
          reference: reference,
          offset: -(rolloverLookbackLimit + 1),
        )!;
        expect(queriedAtLimit.contains(oneBeyond.from), isFalse);
      },
    );
  });
}
