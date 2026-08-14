import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/savings_goals/domain/savings_goal_progress.dart';
import 'package:finos_app/features/savings_goals/domain/savings_goal_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [SavingsGoalProgress]'s derived figures
/// (docs/adr/011-savings-goals.md).
void main() {
  final timestamp = DateTime(2026, 8, 10);

  SavingsGoalRow goalWith({
    int targetAmountMinor = 1000000,
    DateTime? deadlineDate,
    SavingsGoalStatus status = SavingsGoalStatus.active,
  }) => SavingsGoalRow(
    id: 'goal-1',
    name: 'Goal',
    targetAmountMinor: targetAmountMinor,
    currency: 'BDT',
    accountId: 'acct',
    startDate: timestamp,
    deadlineDate: deadlineDate,
    description: '',
    status: status,
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  group('currentAmountMinor', () {
    test('is contributed minus withdrawn', () {
      final progress = SavingsGoalProgress(
        goal: goalWith(),
        contributedMinor: 700000,
        withdrawnMinor: 200000,
      );
      expect(progress.currentAmountMinor, 500000);
    });

    test('is clamped at zero, never negative', () {
      final progress = SavingsGoalProgress(
        goal: goalWith(),
        contributedMinor: 100000,
        withdrawnMinor: 100000,
      );
      expect(progress.currentAmountMinor, 0);
    });
  });

  group('progressFraction', () {
    test('is the current amount over the target', () {
      final progress = SavingsGoalProgress(
        goal: goalWith(targetAmountMinor: 1000000),
        contributedMinor: 250000,
        withdrawnMinor: 0,
      );
      expect(progress.progressFraction, closeTo(0.25, 0.001));
    });

    test('is clamped at 1 even when saved beyond the target', () {
      final progress = SavingsGoalProgress(
        goal: goalWith(targetAmountMinor: 1000000),
        contributedMinor: 1500000,
        withdrawnMinor: 0,
      );
      expect(progress.progressFraction, 1.0);
    });
  });

  group('isAchieved', () {
    test('is false below the target', () {
      final progress = SavingsGoalProgress(
        goal: goalWith(targetAmountMinor: 1000000),
        contributedMinor: 999999,
        withdrawnMinor: 0,
      );
      expect(progress.isAchieved, isFalse);
    });

    test('is true once the current amount reaches the target', () {
      final progress = SavingsGoalProgress(
        goal: goalWith(targetAmountMinor: 1000000),
        contributedMinor: 1000000,
        withdrawnMinor: 0,
      );
      expect(progress.isAchieved, isTrue);
    });

    test(
      'stays true, and does not stop contributions, once saved beyond the target',
      () {
        final progress = SavingsGoalProgress(
          goal: goalWith(targetAmountMinor: 1000000),
          contributedMinor: 1200000,
          withdrawnMinor: 0,
        );
        expect(progress.isAchieved, isTrue);
        expect(progress.goal.status, SavingsGoalStatus.active);
      },
    );
  });

  group('isOverdue', () {
    test('is false with no deadline', () {
      final progress = SavingsGoalProgress(
        goal: goalWith(deadlineDate: null),
        contributedMinor: 0,
        withdrawnMinor: 0,
      );
      expect(progress.isOverdue(now: DateTime(2030, 1, 1)), isFalse);
    });

    test('is true once the deadline has passed and the goal is not achieved', () {
      final progress = SavingsGoalProgress(
        goal: goalWith(
          targetAmountMinor: 1000000,
          deadlineDate: DateTime(2026, 6, 1),
        ),
        contributedMinor: 100000,
        withdrawnMinor: 0,
      );
      expect(progress.isOverdue(now: DateTime(2026, 7, 1)), isTrue);
    });

    test('is false once achieved, even past the deadline', () {
      final progress = SavingsGoalProgress(
        goal: goalWith(
          targetAmountMinor: 1000000,
          deadlineDate: DateTime(2026, 6, 1),
        ),
        contributedMinor: 1000000,
        withdrawnMinor: 0,
      );
      expect(progress.isOverdue(now: DateTime(2026, 7, 1)), isFalse);
    });
  });

  test('maxWithdrawalMinor is exactly the current amount', () {
    final progress = SavingsGoalProgress(
      goal: goalWith(),
      contributedMinor: 700000,
      withdrawnMinor: 200000,
    );
    expect(progress.maxWithdrawalMinor, 500000);
  });

  test('isArchived reflects the stored status', () {
    final progress = SavingsGoalProgress(
      goal: goalWith(status: SavingsGoalStatus.archived),
      contributedMinor: 0,
      withdrawnMinor: 0,
    );
    expect(progress.isArchived, isTrue);
  });
}
