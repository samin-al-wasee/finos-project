import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/reports/domain/monthly_spending.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [monthlySpendingWindows] — the trailing-months window behind the
/// Monthly Spending report (docs/ROADMAP.md §8.4).
void main() {
  test('returns six calendar months, oldest first, ending at the reference '
      'month', () {
    final windows = monthlySpendingWindows(reference: DateTime(2026, 8, 15));

    expect(windows, hasLength(monthlySpendingMonthCount));
    expect(
      windows.first,
      DateRange(from: DateTime(2026, 3), to: DateTime(2026, 4)),
    );
    expect(
      windows.last,
      DateRange(from: DateTime(2026, 8), to: DateTime(2026, 9)),
    );
  });

  test('rolls under the year boundary', () {
    final windows = monthlySpendingWindows(reference: DateTime(2026, 1, 15));

    expect(
      windows.first,
      DateRange(from: DateTime(2025, 8), to: DateTime(2025, 9)),
    );
    expect(
      windows.last,
      DateRange(from: DateTime(2026, 1), to: DateTime(2026, 2)),
    );
  });

  test('each window is a single calendar month', () {
    final windows = monthlySpendingWindows(reference: DateTime(2026, 8, 15));

    for (final window in windows) {
      final expectedTo = DateTime(window.from.year, window.from.month + 1);
      expect(window.to, expectedTo);
    }
  });
}
