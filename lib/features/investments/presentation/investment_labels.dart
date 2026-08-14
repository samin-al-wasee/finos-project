import '../domain/investment_progress.dart';

/// Textual standing, so an investment's state never depends on colour alone
/// (AGENTS.md §21) — the same rule `loanStandingLabel` follows for loans.
String investmentStandingLabel(InvestmentProgress progress) {
  if (progress.isArchived) return 'Archived';
  if (progress.isSettled) return 'Settled';
  if (progress.isMaturityPayoutDue()) return 'Matured — payout due';
  if (progress.isFullyWithdrawn) return 'Fully withdrawn';
  return 'Active';
}
