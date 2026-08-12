import '../../../core/database/app_database.dart';
import 'due_occurrences.dart';

/// One rule's currently-due occurrences, grouped together for display
/// (docs/ROADMAP.md §8.1).
///
/// Occurrences are grouped by rule rather than listed individually so a
/// backlog (the app left unopened for months) reads as "Netflix — 3 due,
/// oldest Jun 5" with bulk actions, not as a wall of identical rows.
class DueRecurringGroup {
  const DueRecurringGroup({required this.rule, required this.due});

  final RecurringTransactionRow rule;
  final DueOccurrences due;
}
