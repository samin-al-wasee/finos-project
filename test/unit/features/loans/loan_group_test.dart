import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/loans/domain/loan_group.dart';
import 'package:finos_app/features/loans/domain/loan_progress.dart';
import 'package:finos_app/features/loans/domain/loan_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// [LoanGroup] and [groupLoanProgress] — a pure, read-time aggregation over
/// per-row [LoanProgress] (docs/adr/006-loan-relationships.md).
///
/// Outstanding and status stay entirely per-row (ADR-004); these tests only
/// cover the group-level rollup, never re-deriving a row's own figures.
void main() {
  LoanProgress loan({
    required String id,
    String? groupId,
    LoanDirection direction = LoanDirection.lent,
    int principalMinor = 2000000,
    int repaidMinor = 0,
    LoanStatus status = LoanStatus.active,
    DateTime? startDate,
    DateTime? dueDate,
  }) {
    return LoanProgress(
      loan: LoanRow(
        id: id,
        type: direction,
        name: 'Loan $id',
        principalMinor: principalMinor,
        currency: 'BDT',
        startDate: startDate ?? DateTime(2026, 1, 1),
        dueDate: dueDate,
        description: '',
        disbursementAccountId: null,
        status: status,
        groupId: groupId,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      repaidMinor: repaidMinor,
      repaymentCount: repaidMinor == 0 ? 0 : 1,
    );
  }

  group('groupLoanProgress', () {
    test('a standalone loan forms a singleton group', () {
      final solo = loan(id: 'loan-1');

      final groups = groupLoanProgress([solo]);

      expect(groups, hasLength(1));
      expect(groups.single.rootId, 'loan-1');
      expect(groups.single.members, [solo]);
      expect(groups.single.isLinked, isFalse);
    });

    test('groups rows sharing a resolved root id', () {
      final root = loan(id: 'loan-1');
      final child = loan(id: 'loan-2', groupId: 'loan-1');
      final unrelated = loan(id: 'loan-3');

      final groups = groupLoanProgress([root, child, unrelated]);

      expect(groups, hasLength(2));
      final relationship = groups.firstWhere((g) => g.rootId == 'loan-1');
      expect(relationship.members, unorderedEquals([root, child]));
      expect(relationship.isLinked, isTrue);

      final singleton = groups.firstWhere((g) => g.rootId == 'loan-3');
      expect(singleton.members, [unrelated]);
      expect(singleton.isLinked, isFalse);
    });
  });

  group('outstandingMinor / principalMinor', () {
    test('sum only active members', () {
      final active1 = loan(
        id: 'loan-1',
        principalMinor: 2000000,
        repaidMinor: 500000,
      );
      final active2 = loan(
        id: 'loan-2',
        groupId: 'loan-1',
        principalMinor: 1000000,
      );
      final archived = loan(
        id: 'loan-3',
        groupId: 'loan-1',
        principalMinor: 5000000,
        status: LoanStatus.archived,
      );

      final group = LoanGroup(
        rootId: 'loan-1',
        members: [active1, active2, archived],
      );

      // (2,000,000 − 500,000) + 1,000,000 — the archived 5,000,000 is excluded.
      expect(group.outstandingMinor, 2500000);
      expect(group.principalMinor, 3000000);
      expect(group.active, [active1, active2]);
    });
  });

  group('isPaid', () {
    test('true only when every active member is paid', () {
      final paid1 = loan(
        id: 'loan-1',
        principalMinor: 2000000,
        repaidMinor: 2000000,
      );
      final paid2 = loan(
        id: 'loan-2',
        groupId: 'loan-1',
        principalMinor: 1000000,
        repaidMinor: 1000000,
      );
      final group = LoanGroup(rootId: 'loan-1', members: [paid1, paid2]);

      expect(group.isPaid, isTrue);
    });

    test(
      'false if any active member still owes, even if others are settled',
      () {
        final paid = loan(
          id: 'loan-1',
          principalMinor: 2000000,
          repaidMinor: 2000000,
        );
        final owing = loan(
          id: 'loan-2',
          groupId: 'loan-1',
          principalMinor: 1000000,
          repaidMinor: 300000,
        );
        final group = LoanGroup(rootId: 'loan-1', members: [paid, owing]);

        expect(group.isPaid, isFalse);
      },
    );

    test('an empty active set (every member archived) is not paid', () {
      final archived = loan(id: 'loan-1', status: LoanStatus.archived);
      final group = LoanGroup(rootId: 'loan-1', members: [archived]);

      expect(group.active, isEmpty);
      expect(group.isPaid, isFalse);
    });
  });

  group('standing', () {
    test('overdue if any active member is overdue', () {
      final onTrack = loan(
        id: 'loan-1',
        startDate: DateTime(2026, 1, 1),
        dueDate: DateTime(2026, 12, 1),
      );
      final overdue = loan(
        id: 'loan-2',
        groupId: 'loan-1',
        startDate: DateTime(2025, 1, 1),
        dueDate: DateTime(2025, 6, 1),
      );
      final group = LoanGroup(rootId: 'loan-1', members: [onTrack, overdue]);

      expect(group.standing(now: DateTime(2026, 8, 1)), LoanStanding.overdue);
    });

    test('paid only when every active member is paid', () {
      final paid1 = loan(
        id: 'loan-1',
        principalMinor: 2000000,
        repaidMinor: 2000000,
      );
      final paid2 = loan(
        id: 'loan-2',
        groupId: 'loan-1',
        principalMinor: 1000000,
        repaidMinor: 1000000,
      );
      final group = LoanGroup(rootId: 'loan-1', members: [paid1, paid2]);

      expect(group.standing(), LoanStanding.paid);
    });

    test('otherwise outstanding', () {
      final owing = loan(id: 'loan-1', principalMinor: 2000000);
      final group = LoanGroup(rootId: 'loan-1', members: [owing]);

      expect(
        group.standing(now: DateTime(2026, 2, 1)),
        LoanStanding.outstanding,
      );
    });
  });

  group('archived members', () {
    test('excluded from active/aggregates but retained in members', () {
      final active = loan(id: 'loan-1', principalMinor: 2000000);
      final archived = loan(
        id: 'loan-2',
        groupId: 'loan-1',
        principalMinor: 9000000,
        status: LoanStatus.archived,
      );
      final group = LoanGroup(rootId: 'loan-1', members: [active, archived]);

      expect(group.members, hasLength(2));
      expect(group.active, [active]);
      expect(group.outstandingMinor, 2000000);
    });
  });

  group('primary', () {
    test('the most recently started active member', () {
      final earlier = loan(id: 'loan-1', startDate: DateTime(2026, 1, 1));
      final later = loan(
        id: 'loan-2',
        groupId: 'loan-1',
        startDate: DateTime(2026, 6, 1),
      );
      final group = LoanGroup(rootId: 'loan-1', members: [earlier, later]);

      expect(group.primary, later);
    });

    test('falls back to the most recent member overall once every member is '
        'archived', () {
      final earlier = loan(
        id: 'loan-1',
        startDate: DateTime(2026, 1, 1),
        status: LoanStatus.archived,
      );
      final later = loan(
        id: 'loan-2',
        groupId: 'loan-1',
        startDate: DateTime(2026, 6, 1),
        status: LoanStatus.archived,
      );
      final group = LoanGroup(rootId: 'loan-1', members: [earlier, later]);

      expect(group.active, isEmpty);
      expect(group.primary, later);
    });
  });
}
