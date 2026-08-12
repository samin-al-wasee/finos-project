import 'quick_command_spec.dart';
import 'quick_field.dart';

/// The result of parsing one line of quick-entry text.
///
/// A pure function of the raw text and the cursor's implied position (the end
/// of the string — the bar has no mid-line editing) — see [parseQuickEntry].
class ParsedQuickCommand {
  const ParsedQuickCommand({
    required this.command,
    required this.values,
    required this.activeFieldIndex,
    required this.suggestionQuery,
  });

  /// The matched top-level command, or `null` while the first word is still
  /// being typed (or doesn't match anything).
  final QuickCommandSpec? command;

  /// Values collected so far, keyed by [QuickField.key]. Only tokens that
  /// don't start with `@` count — an in-progress `@partial` is never treated
  /// as a real value.
  final Map<String, String> values;

  /// Which slot the last token fills: `-1` for the command word itself, `0`
  /// for `command.fields[0]`, `1` for `command.fields[1]`, and so on. Capped
  /// at `command.fields.length - 1` once there are more tokens than fields —
  /// overflow text is appended to the last field rather than discarded.
  final int activeFieldIndex;

  /// The text after `@` in the token currently being typed, or `null` when
  /// that token doesn't start with `@` — i.e. whether to show suggestions at
  /// all, and what to filter them by.
  final String? suggestionQuery;

  /// The field the cursor is currently in, or `null` when it's the command
  /// slot or there is no command yet.
  QuickField? get activeField {
    final spec = command;
    if (spec == null || activeFieldIndex < 0) return null;
    final index = activeFieldIndex.clamp(0, spec.fields.length - 1);
    return spec.fields[index];
  }

  /// Every required field in [command] that has no value yet.
  List<QuickField> get missingRequiredFields {
    final spec = command;
    if (spec == null) return const [];
    return [
      for (final field in spec.fields)
        if (field.required && (values[field.key]?.trim().isEmpty ?? true))
          field,
    ];
  }
}

/// Splits [text] into whitespace-separated tokens, treating a
/// `"double-quoted"` run as a single token (so a suggestion-inserted value
/// with spaces, e.g. an account name, survives being re-parsed). Quotes
/// themselves are stripped from the returned token.
List<String> tokenizeQuickEntry(String text) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  var hasContent = false;

  void flush() {
    if (hasContent) tokens.add(buffer.toString());
    buffer.clear();
    hasContent = false;
  }

  for (final char in text.split('')) {
    if (char == '"') {
      inQuotes = !inQuotes;
      hasContent = true;
      continue;
    }
    if (char == ' ' && !inQuotes) {
      flush();
      continue;
    }
    buffer.write(char);
    hasContent = true;
  }
  flush();
  return tokens;
}

/// Parses one line of quick-entry text into a [ParsedQuickCommand].
///
/// Tokens map to slots purely by position: `tokens[0]` selects the command,
/// `tokens[1]` fills `command.fields[0]`, `tokens[2]` fills
/// `command.fields[1]`, and so on. Extra tokens beyond the last field are
/// appended (space-joined) to that field rather than dropped, so a trailing
/// free-text note doesn't need quoting.
ParsedQuickCommand parseQuickEntry(String text) {
  final tokens = tokenizeQuickEntry(text);

  // A trailing space means the previous token is committed and the cursor is
  // on a fresh, empty slot; otherwise the last token is still being typed.
  final cursorOnFreshSlot = text.isEmpty || text.endsWith(' ');
  final activeTokenIndex = cursorOnFreshSlot
      ? tokens.length
      : tokens.length - 1;

  if (tokens.isEmpty) {
    return const ParsedQuickCommand(
      command: null,
      values: {},
      activeFieldIndex: -1,
      suggestionQuery: null,
    );
  }

  final command = findQuickCommandSpec(tokens.first);

  final values = <String, String>{};
  if (command != null) {
    for (var i = 1; i < tokens.length; i++) {
      // The token the cursor is still typing is never a committed value —
      // that's true whether or not it happens to start with '@'.
      if (i == activeTokenIndex) continue;

      final token = tokens[i];
      if (token.startsWith('@')) continue;

      final fieldIndex = i - 1;
      if (fieldIndex < command.fields.length) {
        final key = command.fields[fieldIndex].key;
        values[key] = token;
      } else {
        final key = command.fields.last.key;
        values[key] = [values[key], token].nonNulls.join(' ');
      }
    }
  }

  final activeFieldIndex = command == null ? -1 : activeTokenIndex - 1;

  final activeToken = activeTokenIndex < tokens.length
      ? tokens[activeTokenIndex]
      : '';
  final suggestionQuery = activeToken.startsWith('@')
      ? activeToken.substring(1)
      : null;

  return ParsedQuickCommand(
    command: command,
    values: values,
    activeFieldIndex: activeFieldIndex,
    suggestionQuery: suggestionQuery,
  );
}

/// Replaces the token at [tokenIndex] in [text] with [value] (quoting it if
/// it contains whitespace) and appends a trailing space, ready for the next
/// slot. Used when the user picks a suggestion.
///
/// [tokenIndex] is `0` for the command slot, `1` for the first field, and so
/// on — one more than [ParsedQuickCommand.activeFieldIndex], which is
/// relative to the command's own field list rather than the raw token list.
String applyQuickEntrySuggestion(String text, int tokenIndex, String value) {
  final tokens = tokenizeQuickEntry(text);
  final kept = tokens.sublist(0, tokenIndex.clamp(0, tokens.length));
  final quoted = value.contains(' ') ? '"$value"' : value;
  return '${[...kept, quoted].join(' ')} ';
}
