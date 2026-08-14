import 'package:finos_app/features/recurring/domain/recurrence_frequency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextOccurrence', () {
    test('daily advances by one calendar day', () {
      expect(
        nextOccurrence(DateTime(2026, 8, 10), RecurrenceFrequency.daily),
        DateTime(2026, 8, 11),
      );
    });

    test('daily rolls over a month boundary', () {
      expect(
        nextOccurrence(DateTime(2026, 8, 31), RecurrenceFrequency.daily),
        DateTime(2026, 9, 1),
      );
    });

    test('weekly advances by seven calendar days', () {
      expect(
        nextOccurrence(DateTime(2026, 8, 10), RecurrenceFrequency.weekly),
        DateTime(2026, 8, 17),
      );
    });

    test('monthly advances by one calendar month, same day', () {
      expect(
        nextOccurrence(DateTime(2026, 8, 15), RecurrenceFrequency.monthly),
        DateTime(2026, 9, 15),
      );
    });

    test('monthly rolls December into January of the next year', () {
      expect(
        nextOccurrence(DateTime(2026, 12, 5), RecurrenceFrequency.monthly),
        DateTime(2027, 1, 5),
      );
    });

    test('monthly clamps the 31st to a shorter month\'s last day', () {
      expect(
        nextOccurrence(DateTime(2026, 1, 31), RecurrenceFrequency.monthly),
        DateTime(2026, 2, 28),
      );
    });

    test('monthly clamps into February in a leap year', () {
      expect(
        nextOccurrence(DateTime(2028, 1, 31), RecurrenceFrequency.monthly),
        DateTime(2028, 2, 29),
      );
    });

    test('quarterly advances by three calendar months, same day', () {
      expect(
        nextOccurrence(DateTime(2026, 8, 15), RecurrenceFrequency.quarterly),
        DateTime(2026, 11, 15),
      );
    });

    test(
      'quarterly clamps the 31st into a shorter month (Jan 31 -> Apr 30)',
      () {
        expect(
          nextOccurrence(DateTime(2026, 1, 31), RecurrenceFrequency.quarterly),
          DateTime(2026, 4, 30),
        );
      },
    );

    test('quarterly rolls across a year boundary', () {
      expect(
        nextOccurrence(DateTime(2026, 11, 5), RecurrenceFrequency.quarterly),
        DateTime(2027, 2, 5),
      );
    });

    test('yearly advances by one calendar year, same day', () {
      expect(
        nextOccurrence(DateTime(2026, 8, 15), RecurrenceFrequency.yearly),
        DateTime(2027, 8, 15),
      );
    });

    test('yearly clamps Feb 29 to Feb 28 in a non-leap year', () {
      expect(
        nextOccurrence(DateTime(2028, 2, 29), RecurrenceFrequency.yearly),
        DateTime(2029, 2, 28),
      );
    });

    test('discards the time component', () {
      expect(
        nextOccurrence(
          DateTime(2026, 8, 10, 23, 59),
          RecurrenceFrequency.daily,
        ),
        DateTime(2026, 8, 11),
      );
    });
  });

  group('recurrenceFrequencyLabel', () {
    test('names every frequency', () {
      expect(recurrenceFrequencyLabel(RecurrenceFrequency.daily), 'Daily');
      expect(recurrenceFrequencyLabel(RecurrenceFrequency.weekly), 'Weekly');
      expect(recurrenceFrequencyLabel(RecurrenceFrequency.monthly), 'Monthly');
      expect(
        recurrenceFrequencyLabel(RecurrenceFrequency.quarterly),
        'Quarterly',
      );
      expect(recurrenceFrequencyLabel(RecurrenceFrequency.yearly), 'Yearly');
    });
  });
}
