import '../../../core/database/app_database.dart';
import '../../accounts/domain/account_status.dart';
import '../../accounts/domain/account_type.dart';
import '../../investments/domain/investment_progress.dart';
import '../../loans/domain/loan_direction.dart';
import '../../loans/domain/loan_progress.dart';
import '../../savings_goals/domain/savings_goal_progress.dart';

/// One line contributing to either side of a net-worth snapshot — an
/// account's balance or a loan's outstanding amount.
class NetWorthEntry {
  const NetWorthEntry({required this.label, required this.amountMinor});

  /// The account's or loan's own name.
  final String label;

  /// This entry's contribution to whichever side it's on.
  final int amountMinor;

  @override
  bool operator ==(Object other) =>
      other is NetWorthEntry &&
      other.label == label &&
      other.amountMinor == amountMinor;

  @override
  int get hashCode => Object.hash(label, amountMinor);
}

/// A snapshot of what the user owns versus what they owe, derived entirely
/// at read time from accounts, loans, and investments (docs/ROADMAP.md §9.1,
/// docs/adr/009-investment-accounting.md) — nothing here is stored.
class NetWorthData {
  const NetWorthData({required this.assets, required this.liabilities});

  final List<NetWorthEntry> assets;
  final List<NetWorthEntry> liabilities;

  int get assetsMinor => assets.fold(0, (sum, e) => sum + e.amountMinor);

  int get liabilitiesMinor =>
      liabilities.fold(0, (sum, e) => sum + e.amountMinor);

  int get netWorthMinor => assetsMinor - liabilitiesMinor;
}

/// Builds [NetWorthData] from already-loaded accounts, their live balances
/// (from `accountBalancesProvider`), loan progress (from
/// `loanProgressProvider`), and investment progress (from
/// `investmentProgressProvider`) — no database access here, so this is
/// directly unit-testable.
///
/// Only active accounts, non-archived loans, and non-archived investments
/// count: archived items are settled or closed, not part of a current
/// snapshot. A credit card contributes its owed amount (`max(0, -balance)`,
/// the same sign convention `CreditCardCycle` documents) as a liability,
/// never as a negative asset; every other account type contributes its
/// balance as an asset as-is — an overdrawn non-credit account still shows as
/// a negative asset entry rather than being reclassified, a deliberate
/// simplification. A loan contributes its outstanding amount as an asset
/// when [LoanDirection.lent] (money owed to the user) or a liability when
/// [LoanDirection.borrowed] (money the user owes).
///
/// An investment contributes its [InvestmentProgress.remainingPrincipalMinor]
/// as an asset — its locked principal, minus anything already withdrawn
/// early (docs/adr/010-investment-early-withdrawal.md) — until
/// [InvestmentProgress.isSettled] (its maturity payout has actually been
/// recorded), at which point it contributes nothing. For every investment
/// with no early withdrawal, `remainingPrincipalMinor` equals
/// `contributedMinor`, so this is unchanged from before that ADR. A
/// *periodic* payout (e.g. Sanchayapatra's quarterly profit) never reduces
/// this: it is new profit credited to the payout account, not a return of
/// principal, and is already counted there via [balances] — so unlike
/// [payoutReceivedMinor] as a whole, only a withdrawal or the maturity
/// settlement reduces this (docs/adr/009-investment-accounting.md,
/// docs/adr/010-investment-early-withdrawal.md).
///
/// A savings goal contributes its [SavingsGoalProgress.currentAmountMinor]
/// as an asset while not archived — safe from double-counting because a
/// contribution genuinely debits the goal's linked account, the same
/// reasoning that makes an investment's principal a separate asset line
/// rather than still being inside any account's balance
/// (docs/adr/011-savings-goals.md).
NetWorthData computeNetWorth({
  required List<FinancialAccountRow> accounts,
  required Map<String, int> balances,
  required List<LoanProgress> loans,
  List<InvestmentProgress> investments = const [],
  List<SavingsGoalProgress> savingsGoals = const [],
}) {
  final assets = <NetWorthEntry>[];
  final liabilities = <NetWorthEntry>[];

  for (final account in accounts) {
    if (account.status != AccountStatus.active) continue;
    final balance = balances[account.id] ?? account.openingBalanceMinor;
    if (account.type == AccountType.creditCard) {
      final owed = balance < 0 ? -balance : 0;
      if (owed > 0) {
        liabilities.add(NetWorthEntry(label: account.name, amountMinor: owed));
      }
    } else {
      assets.add(NetWorthEntry(label: account.name, amountMinor: balance));
    }
  }

  for (final progress in loans) {
    if (progress.isArchived || progress.outstandingMinor == 0) continue;
    final entry = NetWorthEntry(
      label: progress.loan.name,
      amountMinor: progress.outstandingMinor,
    );
    if (progress.direction == LoanDirection.lent) {
      assets.add(entry);
    } else {
      liabilities.add(entry);
    }
  }

  for (final progress in investments) {
    if (progress.isArchived || progress.isSettled) continue;
    if (progress.remainingPrincipalMinor <= 0) continue;
    assets.add(
      NetWorthEntry(
        label: progress.investment.name,
        amountMinor: progress.remainingPrincipalMinor,
      ),
    );
  }

  for (final progress in savingsGoals) {
    if (progress.isArchived || progress.currentAmountMinor <= 0) continue;
    assets.add(
      NetWorthEntry(
        label: progress.goal.name,
        amountMinor: progress.currentAmountMinor,
      ),
    );
  }

  return NetWorthData(assets: assets, liabilities: liabilities);
}
