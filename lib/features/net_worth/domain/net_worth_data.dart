import '../../../core/database/app_database.dart';
import '../../accounts/domain/account_status.dart';
import '../../accounts/domain/account_type.dart';
import '../../loans/domain/loan_direction.dart';
import '../../loans/domain/loan_progress.dart';

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
/// at read time from accounts and loans (docs/ROADMAP.md §9.1) — nothing
/// here is stored.
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
/// (from `accountBalancesProvider`), and loan progress (from
/// `loanProgressProvider`) — no database access here, so this is directly
/// unit-testable.
///
/// Only active accounts and non-archived loans count: archived items are
/// settled or closed, not part of a current snapshot. A credit card
/// contributes its owed amount (`max(0, -balance)`, the same sign
/// convention `CreditCardCycle` documents) as a liability, never as a
/// negative asset; every other account type contributes its balance as an
/// asset as-is — an overdrawn non-credit account still shows as a negative
/// asset entry rather than being reclassified, a deliberate simplification.
/// A loan contributes its outstanding amount as an asset when
/// [LoanDirection.lent] (money owed to the user) or a liability when
/// [LoanDirection.borrowed] (money the user owes).
NetWorthData computeNetWorth({
  required List<FinancialAccountRow> accounts,
  required Map<String, int> balances,
  required List<LoanProgress> loans,
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

  return NetWorthData(assets: assets, liabilities: liabilities);
}
