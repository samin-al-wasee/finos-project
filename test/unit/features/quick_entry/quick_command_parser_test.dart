import 'package:finos_app/features/quick_entry/domain/quick_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the quick-entry grammar: [tokenizeQuickEntry], [parseQuickEntry],
/// and [applyQuickEntrySuggestion].
void main() {
  group('tokenizeQuickEntry', () {
    test('splits on whitespace', () {
      expect(tokenizeQuickEntry('income 500 today'), [
        'income',
        '500',
        'today',
      ]);
    });

    test('collapses repeated spaces', () {
      expect(tokenizeQuickEntry('income   500'), ['income', '500']);
    });

    test('keeps a quoted run as one token, stripping the quotes', () {
      expect(tokenizeQuickEntry('expense 500 today "Main Bank"'), [
        'expense',
        '500',
        'today',
        'Main Bank',
      ]);
    });

    test('an empty string tokenizes to nothing', () {
      expect(tokenizeQuickEntry(''), isEmpty);
      expect(tokenizeQuickEntry('   '), isEmpty);
    });
  });

  group('parseQuickEntry — command slot', () {
    test('an empty line has no command and is on the command slot', () {
      final parsed = parseQuickEntry('');
      expect(parsed.command, isNull);
      expect(parsed.activeFieldIndex, -1);
      expect(parsed.suggestionQuery, isNull);
    });

    test('"@" alone requests every top-level suggestion', () {
      final parsed = parseQuickEntry('@');
      expect(parsed.command, isNull);
      expect(parsed.suggestionQuery, '');
    });

    test('"@inc" filters the top-level suggestions', () {
      final parsed = parseQuickEntry('@inc');
      expect(parsed.command, isNull);
      expect(parsed.suggestionQuery, 'inc');
    });

    test('a matched command word (case-insensitive) selects the command', () {
      expect(parseQuickEntry('Income').command?.key, 'income');
      expect(parseQuickEntry('INCOME ').command?.key, 'income');
    });

    test('an unmatched command word leaves command null', () {
      expect(parseQuickEntry('nonsense').command, isNull);
    });
  });

  group('parseQuickEntry — field slots', () {
    test('positional tokens fill fields in order', () {
      final parsed = parseQuickEntry('income 500 2026-08-01 "Main Bank" ');
      expect(parsed.command?.key, 'income');
      expect(parsed.values['amount'], '500');
      expect(parsed.values['date'], '2026-08-01');
      expect(parsed.values['account'], 'Main Bank');
    });

    test(
      'without a trailing space, the last token is active — not yet a value',
      () {
        final parsed = parseQuickEntry('income 500');
        expect(parsed.values.containsKey('amount'), isFalse);
        expect(parsed.activeFieldIndex, 0);
        expect(parsed.command?.fields[0].key, 'amount');
      },
    );

    test('a trailing space moves the cursor to the next, empty slot', () {
      final parsed = parseQuickEntry('income 500 ');
      expect(parsed.values['amount'], '500');
      expect(parsed.activeFieldIndex, 1);
      expect(parsed.command?.fields[1].key, 'date');
    });

    test('a token starting with @ is never a committed value', () {
      final parsed = parseQuickEntry('income 500 @');
      expect(parsed.values.containsKey('date'), isFalse);
      expect(parsed.suggestionQuery, '');
    });

    test('@ with trailing text filters that slot\'s suggestions', () {
      final parsed = parseQuickEntry('expense 500 today @ma');
      expect(parsed.activeField?.key, 'account');
      expect(parsed.suggestionQuery, 'ma');
    });

    test('extra tokens beyond the last field append to it, space-joined', () {
      final parsed = parseQuickEntry(
        'income 500 today "Main Bank" Salary a nice bonus ',
      );
      // fields: amount, date, account, category, description — "description"
      // is the last field, so everything past it accumulates there.
      expect(parsed.values['description'], 'a nice bonus');
    });

    test('missingRequiredFields lists only required, still-blank fields', () {
      final parsed = parseQuickEntry('income 500 ');
      final keys = parsed.missingRequiredFields.map((f) => f.key).toList();
      expect(keys, contains('account'));
      expect(keys, isNot(contains('category'))); // optional
      expect(keys, isNot(contains('amount'))); // already filled
    });

    test('missingRequiredFields is empty with no command', () {
      expect(parseQuickEntry('@').missingRequiredFields, isEmpty);
    });
  });

  group('applyQuickEntrySuggestion', () {
    test('fills the command slot (index 0)', () {
      expect(applyQuickEntrySuggestion('@', 0, 'income'), 'income ');
    });

    test('replaces the in-progress token at a later slot', () {
      final result = applyQuickEntrySuggestion(
        'income 500 today @ma',
        3,
        'Main Bank',
      );
      expect(result, 'income 500 today "Main Bank" ');
    });

    test('quotes a value containing spaces', () {
      expect(
        applyQuickEntrySuggestion('income 500 today @', 3, 'Main Bank'),
        'income 500 today "Main Bank" ',
      );
    });

    test('leaves a single-word value unquoted', () {
      expect(
        applyQuickEntrySuggestion('expense 500 today @', 3, 'Groceries'),
        'expense 500 today Groceries ',
      );
    });
  });
}
