import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../../accounts/data/account_dao.dart';
import '../../accounts/domain/account_status.dart';
import '../../budgets/domain/budget_period.dart' show dayStart;
import '../../recurring/domain/due_occurrences.dart';
import '../../recurring/domain/recurrence_frequency.dart';
import '../../transactions/data/transaction_dao.dart';
import '../../transactions/domain/transaction_type.dart';
import '../data/investment_dao.dart';
import '../domain/investment_contribution_mode.dart';
import '../domain/investment_instrument_type.dart';
import '../domain/investment_payout_frequency.dart';
import '../domain/investment_progress.dart';
import '../domain/investment_status.dart';

/// Application-service for the investment lifecycle
/// (docs/adr/009-investment-accounting.md).
///
/// Owns the rules that keep an investment and the money behind it in step,
/// the same role [LoanController] plays for loans:
///
/// * creating a lump-sum investment records its contribution transaction
///   atomically; a recurring one (DPS) creates none — the first installment
///   becomes due like any other recurring item, never auto-created
///   (docs/ARCHITECTURE.md §20)
/// * a contribution or payout is a transaction carrying the investment's id
/// * confirming a due contribution or payout is the only way one is ever
///   created — nothing here creates a transaction unprompted
class InvestmentController {
  InvestmentController(
    this._database,
    this._dao,
    this._transactions,
    this._accounts,
  );

  final AppDatabase _database;
  final InvestmentDao _dao;
  final TransactionDao _transactions;
  final AccountDao _accounts;

  /// Creates an investment, and its contribution transaction when
  /// [contributionMode] is [InvestmentContributionMode.lumpSum].
  ///
  /// For [InvestmentContributionMode.recurring] (DPS), no transaction is
  /// created here — `nextContributionDue` is set to [startDate], the same
  /// "due today" convention `RecurringTransactionController.create` uses, and
  /// the first installment must be confirmed like any other due occurrence.
  ///
  /// When [payoutFrequency] is periodic, `nextPayoutDue` is the *first*
  /// occurrence after [startDate] rather than [startDate] itself — unlike a
  /// contribution, a payout is profit the instrument has not yet had time to
  /// accrue, so it cannot plausibly be due on the day the instrument opens.
  ///
  /// Returns the generated investment id.
  Future<String> create({
    required String name,
    required InvestmentInstrumentType instrumentType,
    required InvestmentContributionMode contributionMode,
    required int amountMinor,
    required String sourceAccountId,
    required String payoutAccountId,
    required DateTime maturityDate,
    InvestmentPayoutFrequency payoutFrequency =
        const InvestmentPayoutFrequency.atMaturity(),
    DateTime? startDate,
    String currency = 'BDT',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Enter a name for this investment');
    }
    if (amountMinor <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }

    final start = dayStart(startDate ?? DateTime.now());
    final maturity = dayStart(maturityDate);
    if (!maturity.isAfter(start)) {
      throw ArgumentError('The maturity date must be after the start date');
    }

    await _requireActiveAccount(sourceAccountId);
    await _requireActiveAccount(payoutAccountId);

    final id = generateId();
    final nextContributionDue =
        contributionMode == InvestmentContributionMode.recurring ? start : null;
    final payoutFrequencyValue = payoutFrequency.periodic;
    final nextPayoutDue = payoutFrequencyValue == null
        ? null
        : nextOccurrence(start, payoutFrequencyValue);

    // One transaction so a lump-sum investment can never be left without the
    // contribution that created it, or the contribution without its
    // investment.
    await _database.transaction(() async {
      await _dao.insertOne(
        InvestmentsCompanion.insert(
          id: id,
          name: trimmedName,
          instrumentType: instrumentType,
          contributionMode: contributionMode,
          amountMinor: amountMinor,
          currency: Value(currency),
          sourceAccountId: sourceAccountId,
          payoutAccountId: payoutAccountId,
          startDate: start,
          maturityDate: maturity,
          payoutFrequency: payoutFrequency,
          nextContributionDue: Value(nextContributionDue),
          nextPayoutDue: Value(nextPayoutDue),
        ),
      );

      if (contributionMode == InvestmentContributionMode.lumpSum) {
        await _transactions.insertOne(
          TransactionsCompanion.insert(
            id: generateId(),
            type: TransactionType.investmentContribution,
            amountMinor: amountMinor,
            currency: Value(currency),
            accountId: sourceAccountId,
            // Investment movements never carry a category, so they cannot
            // reach spending analytics or budgets
            // (docs/adr/009-investment-accounting.md).
            categoryId: const Value(null),
            investmentId: Value(id),
            date: start,
            description: Value('Contribution · $trimmedName'),
          ),
        );
      }
    });

    return id;
  }

  /// Confirms the oldest due contribution installment (DPS only): creates its
  /// transaction, for the fixed [InvestmentRow.amountMinor] — unlike a
  /// payout, an installment's amount is fixed by definition, so there is
  /// nothing for the caller to supply — and advances `nextContributionDue`.
  ///
  /// Does nothing if there is no due contribution. Throws [StateError] if the
  /// investment does not exist.
  Future<void> confirmNextContribution(String id) async {
    final investment = await _dao.getById(id);
    if (investment == null) throw StateError('Investment not found: $id');

    final nextDue = investment.nextContributionDue;
    if (nextDue == null) return;
    final due = dueOccurrences(
      from: nextDue,
      frequency: RecurrenceFrequency.monthly,
      asOf: DateTime.now(),
      endDate: investment.maturityDate,
    );
    if (due.dates.isEmpty) return;

    await _database.transaction(() async {
      await _transactions.insertOne(
        TransactionsCompanion.insert(
          id: generateId(),
          type: TransactionType.investmentContribution,
          amountMinor: investment.amountMinor,
          currency: Value(investment.currency),
          accountId: investment.sourceAccountId,
          categoryId: const Value(null),
          investmentId: Value(id),
          date: due.dates.first,
          description: Value('Contribution · ${investment.name}'),
        ),
      );
      await _dao.updateOne(
        investment.copyWith(
          nextContributionDue: Value(
            nextOccurrence(due.dates.first, RecurrenceFrequency.monthly),
          ),
          updatedAt: DateTime.now(),
        ),
      );
    });
  }

  /// Skips the oldest due contribution installment: advances
  /// `nextContributionDue` without creating a transaction.
  ///
  /// Does nothing if there is no due contribution. Throws [StateError] if the
  /// investment does not exist.
  Future<void> skipNextContribution(String id) async {
    final investment = await _dao.getById(id);
    if (investment == null) throw StateError('Investment not found: $id');

    final nextDue = investment.nextContributionDue;
    if (nextDue == null) return;
    final due = dueOccurrences(
      from: nextDue,
      frequency: RecurrenceFrequency.monthly,
      asOf: DateTime.now(),
      endDate: investment.maturityDate,
    );
    if (due.dates.isEmpty) return;

    await _dao.updateOne(
      investment.copyWith(
        nextContributionDue: Value(
          nextOccurrence(due.dates.first, RecurrenceFrequency.monthly),
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Confirms a payout: creates a transaction for [amountMinor] and advances
  /// `nextPayoutDue` when this instrument pays periodically.
  ///
  /// Unlike a contribution installment, [amountMinor] must be supplied by the
  /// caller rather than read from the investment row: real interest/profit is
  /// bank-computed and this app must never guess at money
  /// (docs/adr/009-investment-accounting.md). This same method handles both
  /// a routine periodic profit payout and the final maturity payout — the
  /// caller distinguishes the two only in how it labels the action, driven by
  /// [InvestmentProgress.isMaturityPayoutDue].
  ///
  /// Throws [ArgumentError] if [amountMinor] is not positive, and
  /// [StateError] if the investment does not exist.
  Future<String> confirmNextPayout(
    String id, {
    required int amountMinor,
    DateTime? date,
  }) async {
    if (amountMinor <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }

    final investment = await _dao.getById(id);
    if (investment == null) throw StateError('Investment not found: $id');

    final payoutDate = dayStart(date ?? DateTime.now());
    final transactionId = generateId();

    await _database.transaction(() async {
      await _transactions.insertOne(
        TransactionsCompanion.insert(
          id: transactionId,
          type: TransactionType.investmentPayout,
          amountMinor: amountMinor,
          currency: Value(investment.currency),
          accountId: investment.payoutAccountId,
          categoryId: const Value(null),
          investmentId: Value(id),
          date: payoutDate,
          description: Value('Payout · ${investment.name}'),
        ),
      );

      final periodic = investment.payoutFrequency.periodic;
      if (periodic != null && investment.nextPayoutDue != null) {
        await _dao.updateOne(
          investment.copyWith(
            nextPayoutDue: Value(nextOccurrence(payoutDate, periodic)),
            updatedAt: DateTime.now(),
          ),
        );
      }
    });

    return transactionId;
  }

  /// Skips the oldest due periodic payout: advances `nextPayoutDue` without
  /// creating a transaction.
  ///
  /// Does nothing if this instrument has no periodic payout schedule or none
  /// is due. Throws [StateError] if the investment does not exist.
  Future<void> skipNextPayout(String id) async {
    final investment = await _dao.getById(id);
    if (investment == null) throw StateError('Investment not found: $id');

    final periodic = investment.payoutFrequency.periodic;
    final nextDue = investment.nextPayoutDue;
    if (periodic == null || nextDue == null) return;
    final due = dueOccurrences(
      from: nextDue,
      frequency: periodic,
      asOf: DateTime.now(),
      endDate: investment.maturityDate,
    );
    if (due.dates.isEmpty) return;

    await _dao.updateOne(
      investment.copyWith(
        nextPayoutDue: Value(nextOccurrence(due.dates.first, periodic)),
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Updates the editable fields of an investment.
  ///
  /// The instrument type, contribution mode, amount, accounts, and dates are
  /// fixed at creation: changing any of them would leave already-recorded
  /// contributions/payouts describing an investment that no longer exists —
  /// the same reasoning `LoanController.update` applies to a loan's
  /// principal and disbursement account.
  Future<void> update({required String id, required String name}) async {
    final row = await _dao.getById(id);
    if (row == null) throw StateError('Investment not found: $id');

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Enter a name for this investment');
    }

    await _dao.updateOne(
      row.copyWith(name: trimmedName, updatedAt: DateTime.now()),
    );
  }

  /// Archives an investment, keeping it and its transactions for reference.
  ///
  /// Reversible from any state, including once matured — the same as
  /// [LoanController.archive] treats a paid-off loan.
  Future<void> archive(String id) =>
      _dao.updateStatus(id, InvestmentStatus.archived);

  /// Re-activates an archived investment.
  Future<void> restore(String id) =>
      _dao.updateStatus(id, InvestmentStatus.active);

  /// Permanently deletes an investment that has no *confirmed* activity.
  ///
  /// A lump-sum investment's own origination contribution goes with it, in
  /// one database transaction — the same as a loan's origination movement
  /// (`LoanController.delete`): it was created automatically by [create],
  /// not a separate confirmed action, so deleting the investment right after
  /// creating it by mistake must not require archiving instead. What *does*
  /// block deletion is any payout (periodic profit or maturity proceeds), or
  /// — for a recurring (DPS) investment — any contribution, because each one
  /// there was a distinct action the user explicitly confirmed
  /// (docs/adr/009-investment-accounting.md). Those are financial history;
  /// archiving is the correct way to retire the investment instead
  /// (docs/DATA_MODEL.md §47).
  Future<void> delete(String id) async {
    final investment = await _dao.getById(id);
    if (investment == null) throw StateError('Investment not found: $id');

    final hasPayout = await _transactions.hasInvestmentMovement(
      id,
      TransactionType.investmentPayout,
    );
    final hasConfirmedContribution =
        investment.contributionMode == InvestmentContributionMode.recurring &&
        await _transactions.hasInvestmentMovement(
          id,
          TransactionType.investmentContribution,
        );
    if (hasPayout || hasConfirmedContribution) {
      throw ArgumentError(
        'This investment has contributions or payouts recorded. Archive it '
        'instead of deleting it.',
      );
    }

    await _database.transaction(() async {
      await _transactions.deleteForInvestment(id);
      await _dao.deleteOne(id);
    });
  }

  /// Returns the investment identified by [id], or `null` if not found.
  Future<InvestmentRow?> getById(String id) => _dao.getById(id);

  /// Derives everything about [investment] that depends on its transactions.
  Future<InvestmentProgress> progressFor(InvestmentRow investment) async {
    final contributedMinor = await _transactions.investmentMovementTotal(
      investment.id,
      TransactionType.investmentContribution,
    );
    final payoutReceivedMinor = await _transactions.investmentMovementTotal(
      investment.id,
      TransactionType.investmentPayout,
    );
    final movements = await _transactions.forInvestment(investment.id);
    final payoutDates =
        movements
            .where((row) => row.type == TransactionType.investmentPayout)
            .map((row) => row.date)
            .toList()
          ..sort();

    return InvestmentProgress(
      investment: investment,
      contributedMinor: contributedMinor,
      payoutReceivedMinor: payoutReceivedMinor,
      latestPayoutDate: payoutDates.isEmpty ? null : payoutDates.last,
    );
  }

  Future<void> _requireActiveAccount(String accountId) async {
    final account = await _accounts.getById(accountId);
    if (account == null) throw StateError('Account not found: $accountId');
    if (account.status != AccountStatus.active) {
      throw StateError('Account is not active: ${account.name}');
    }
  }
}
