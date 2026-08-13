/// Whether a list⇄card screen (Accounts, Loans, Budgets) shows every row as a
/// plain list, or one at a time as a swipeable card (docs/ROADMAP.md
/// §8.9–§8.11). List stays the default.
enum ListViewMode { list, card }

/// Canonical uppercase storage value for each view mode.
const Map<ListViewMode, String> _storage = {
  ListViewMode.list: 'LIST',
  ListViewMode.card: 'CARD',
};

/// Serialises [mode] to its storage value.
String listViewModeToStorage(ListViewMode mode) => _storage[mode]!;

/// Parses a stored view-mode value, falling back to [ListViewMode.list].
///
/// Unrecognised and null values fall back rather than throwing: a settings row
/// written by a future version of the app must never make the app unlaunchable.
ListViewMode listViewModeFromStorage(String? value) {
  if (value == null) return ListViewMode.list;
  for (final entry in _storage.entries) {
    if (entry.value == value) return entry.key;
  }
  return ListViewMode.list;
}
