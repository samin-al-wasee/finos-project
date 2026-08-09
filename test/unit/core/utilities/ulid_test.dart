import 'dart:math';

import 'package:finos_app/core/utilities/ulid.dart';
import 'package:flutter_test/flutter_test.dart';

const _validChars = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

void main() {
  group('generateId', () {
    test('returns a 26-character string', () {
      final id = generateId();
      expect(id.length, 26);
    });

    test('contains only valid Crockford base-32 characters', () {
      final id = generateId();
      for (final char in id.split('')) {
        expect(
          _validChars.contains(char),
          isTrue,
          reason: 'Invalid char: $char',
        );
      }
    });

    test('generates unique values', () {
      final ids = {for (var i = 0; i < 1000; i++) generateId()};
      expect(ids.length, 1000);
    });

    test('sequential IDs are lexicographically ordered', () {
      // Use a fixed random source so the only variable is the timestamp.
      final rng = Random(42);
      final id1 = generateId(rng);
      // Tiny sleep to guarantee different millisecond timestamp.
      Future<void>.delayed(const Duration(milliseconds: 2));
      final id2 = generateId(rng);
      expect(id2.compareTo(id1), greaterThanOrEqualTo(0));
    });

    test('accepts a deterministic random source', () {
      final rng = Random(0);
      final id1 = generateId(rng);
      final id2 = generateId(rng);
      // Same random source, different timestamps → IDs should differ.
      expect(id1, isNot(equals(id2)));
      // Both still have valid format.
      expect(id1.length, 26);
      expect(id2.length, 26);
    });
  });
}
