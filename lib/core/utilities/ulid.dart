import 'dart:math';

/// Crockford base-32 alphabet (excludes I, L, O, U).
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Generates a ULID (Universally Unique Lexicographically Sortable Identifier).
///
/// Returns a 26-character string: 10 chars for a millisecond-precision Unix
/// timestamp followed by 16 chars of cryptographic randomness. The result is
/// lexicographically sortable by creation time.
///
/// An optional [random] source can be injected for deterministic tests.
String generateId([Random? random]) {
  final rng = random ?? Random.secure();
  final timestamp = DateTime.now().millisecondsSinceEpoch;

  // 48-bit timestamp → 10 base-32 chars.
  final ts = _encodeBase32(timestamp, 10);

  // 80-bit random → 16 base-32 chars (two 40-bit halves).
  final highBytes = List<int>.generate(5, (_) => rng.nextInt(256));
  final lowBytes = List<int>.generate(5, (_) => rng.nextInt(256));
  final high = highBytes.fold<int>(0, (v, b) => (v << 8) | b);
  final low = lowBytes.fold<int>(0, (v, b) => (v << 8) | b);
  final rnd = _encodeBase32(high, 8) + _encodeBase32(low, 8);

  return '$ts$rnd';
}

/// Encodes a [value] into exactly [length] Crockford base-32 characters.
///
/// Only the lowest `length * 5` bits of [value] are used.
String _encodeBase32(int value, int length) {
  final buffer = StringBuffer();
  for (var i = length - 1; i >= 0; i--) {
    buffer.write(_alphabet[(value >> (i * 5)) & 0x1F]);
  }
  return buffer.toString();
}
