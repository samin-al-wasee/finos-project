import '../domain/loan_direction.dart';
import '../domain/loan_progress.dart';

/// Section heading for a loan direction (docs/UI_DESIGN.md §21).
///
/// Deliberately phrased from the user's point of view — "I Owe" and "Owed to Me"
/// leave no room for the ambiguity that "lent"/"borrowed" invites.
String loanDirectionHeading(LoanDirection direction) {
  switch (direction) {
    case LoanDirection.borrowed:
      return 'I Owe';
    case LoanDirection.lent:
      return 'Owed to Me';
  }
}

/// Short label for a loan direction, used on the details screen.
String loanDirectionLabel(LoanDirection direction) {
  switch (direction) {
    case LoanDirection.borrowed:
      return 'I owe';
    case LoanDirection.lent:
      return 'Owed to me';
  }
}

/// Wording for the option in the loan form.
String loanDirectionOption(LoanDirection direction) {
  switch (direction) {
    case LoanDirection.borrowed:
      return 'Money I borrowed';
    case LoanDirection.lent:
      return 'Money I lent';
  }
}

/// Textual standing, so a loan's state never depends on colour alone
/// (AGENTS.md §21).
String loanStandingLabel(LoanStanding standing) {
  switch (standing) {
    case LoanStanding.outstanding:
      return 'Outstanding';
    case LoanStanding.overdue:
      return 'Overdue';
    case LoanStanding.paid:
      return 'Fully repaid';
  }
}

/// What a repayment does, from the user's side.
String repaymentActionLabel(LoanDirection direction) {
  switch (direction) {
    case LoanDirection.borrowed:
      return 'Record payment';
    case LoanDirection.lent:
      return 'Record receipt';
  }
}
