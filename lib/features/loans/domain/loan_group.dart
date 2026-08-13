import 'loan_direction.dart';
import 'loan_progress.dart';

/// A relationship of one or more linked loans, aggregated for display
/// (docs/adr/006-loan-relationships.md).
///
/// Grouping is a read-time, in-memory concept only. Outstanding and status stay
/// entirely per-row, computed by the unmodified ADR-004 [LoanProgress] rules; a
/// group's figures are purely derived from its members' figures and are never
/// stored or fed back into a row.
class LoanGroup {
  const LoanGroup({required this.rootId, required this.members})
    : assert(members.length > 0, 'A loan group must have at least one member');

  /// The id of the relationship's root loan — the first one created. Every
  /// member's `groupId` (or, for the root itself, its own `id`) resolves to
  /// this value.
  final String rootId;

  /// Every loan in the relationship, including archived ones, so the
  /// Related-loans display can still show them.
  final List<LoanProgress> members;

  /// Which way every loan in the group runs. Extending or linking a loan
  /// requires matching direction (`LoanController.create`), so every member
  /// shares the same one.
  LoanDirection get direction => members.first.direction;

  /// Members that are not archived — the ones a group's aggregates count.
  List<LoanProgress> get active => members.where((m) => !m.isArchived).toList();

  /// Combined outstanding amount across the group's active members.
  int get outstandingMinor =>
      active.fold<int>(0, (sum, m) => sum + m.outstandingMinor);

  /// Combined principal across the group's active members.
  int get principalMinor =>
      active.fold<int>(0, (sum, m) => sum + m.principalMinor);

  /// True only when every active member is fully repaid. An empty [active]
  /// (every member archived) is not considered paid.
  bool get isPaid => active.isNotEmpty && active.every((m) => m.isPaid);

  /// The group's derived standing: overdue if any active member is overdue,
  /// paid only if every active member is paid, otherwise outstanding.
  LoanStanding standing({DateTime? now}) {
    if (active.any((m) => m.isOverdue(now: now))) return LoanStanding.overdue;
    if (isPaid) return LoanStanding.paid;
    return LoanStanding.outstanding;
  }

  /// The member a screen should treat as "the" loan for this group: the most
  /// recently started active member, or — once every member is archived —
  /// the most recently started member overall.
  LoanProgress get primary {
    final pool = active.isNotEmpty ? active : members;
    return pool.reduce(
      (a, b) => b.loan.startDate.isAfter(a.loan.startDate) ? b : a,
    );
  }

  /// Whether this "group" is actually more than one loan.
  bool get isLinked => members.length > 1;
}

/// Groups [all] loans' progress into relationships, keyed by each loan's
/// resolved root id (`groupId ?? id`) — a flat, single-level grouping with no
/// recursive traversal, mirroring how `group_id` is stored
/// (docs/adr/006-loan-relationships.md).
///
/// A loan that has never been linked forms a singleton group of one.
List<LoanGroup> groupLoanProgress(List<LoanProgress> all) {
  final byRoot = <String, List<LoanProgress>>{};
  for (final progress in all) {
    final rootId = progress.loan.groupId ?? progress.loan.id;
    byRoot.putIfAbsent(rootId, () => []).add(progress);
  }
  return [
    for (final entry in byRoot.entries)
      LoanGroup(rootId: entry.key, members: entry.value),
  ];
}
