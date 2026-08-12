import 'package:finos_app/features/recurring/domain/due_occurrences.dart';
import 'package:finos_app/features/recurring/domain/recurrence_frequency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dueOccurrences', () {
    test('nothing is due before the next occurrence', () {
      final result = dueOccurrences(
        from: DateTime(2026, 9, 1),
        frequency: RecurrenceFrequency.monthly,
        asOf: DateTime(2026, 8, 15),
      );
      expect(result.dates, isEmpty);
      expect(result.totalCount, 0);
      expect(result.isCapped, isFalse);
    });

    test('exactly one occurrence when next falls on asOf', () {
      final result = dueOccurrences(
        from: DateTime(2026, 8, 15),
        frequency: RecurrenceFrequency.monthly,
        asOf: DateTime(2026, 8, 15),
      );
      expect(result.dates, [DateTime(2026, 8, 15)]);
      expect(result.totalCount, 1);
    });

    test('collects every occurrence up to asOf, oldest first', () {
      final result = dueOccurrences(
        from: DateTime(2026, 6, 1),
        frequency: RecurrenceFrequency.monthly,
        asOf: DateTime(2026, 9, 10),
      );
      expect(result.dates, [
        DateTime(2026, 6, 1),
        DateTime(2026, 7, 1),
        DateTime(2026, 8, 1),
        DateTime(2026, 9, 1),
      ]);
      expect(result.totalCount, 4);
      expect(result.isCapped, isFalse);
    });

    test('stops at the end date even if asOf is later', () {
      final result = dueOccurrences(
        from: DateTime(2026, 6, 1),
        frequency: RecurrenceFrequency.monthly,
        asOf: DateTime(2026, 12, 1),
        endDate: DateTime(2026, 8, 1),
      );
      expect(result.dates, [
        DateTime(2026, 6, 1),
        DateTime(2026, 7, 1),
        DateTime(2026, 8, 1),
      ]);
    });

    test('caps the returned dates but reports the true total', () {
      final result = dueOccurrences(
        from: DateTime(2026, 1, 1),
        frequency: RecurrenceFrequency.daily,
        asOf: DateTime(2026, 6, 1), // ~150 days, well past the cap
      );
      expect(result.dates, hasLength(maxDueOccurrences));
      expect(result.totalCount, greaterThan(maxDueOccurrences));
      expect(result.isCapped, isTrue);
      // The cap keeps the oldest occurrences, not the newest.
      expect(result.dates.first, DateTime(2026, 1, 1));
    });

    test('discards the time component of every bound', () {
      final result = dueOccurrences(
        from: DateTime(2026, 8, 15, 8),
        frequency: RecurrenceFrequency.daily,
        asOf: DateTime(2026, 8, 15, 23, 59),
      );
      expect(result.dates, [DateTime(2026, 8, 15)]);
    });
  });
}
