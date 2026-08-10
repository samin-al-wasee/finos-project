import '../../../core/database/app_database.dart';
import 'transaction_type.dart';

/// The type groupings a user can filter by (FR-02, docs/ROADMAP.md §6.2).
///
/// [loan] covers both [TransactionType.loanReceipt] and
/// [TransactionType.loanPayment]: to a user filtering their history, a loan
/// disbursement and a loan repayment are both "loan activity," not two
/// unrelated types.
enum TransactionTypeFilter { income, expense, transfer, loan }

/// Maps a stored [TransactionType] to the [TransactionTypeFilter] it belongs to.
TransactionTypeFilter typeFilterFor(TransactionType type) {
  switch (type) {
    case TransactionType.income:
      return TransactionTypeFilter.income;
    case TransactionType.expense:
      return TransactionTypeFilter.expense;
    case TransactionType.transfer:
      return TransactionTypeFilter.transfer;
    case TransactionType.loanReceipt:
    case TransactionType.loanPayment:
      return TransactionTypeFilter.loan;
  }
}

/// Search and filter criteria for the transaction list (FR-02).
///
/// This is basic, single-dimension filtering — one account, one category, a
/// set of types, a date range, and a text search. Compound criteria like "food
/// transactions between ৳500 and ৳2,000 in July" are explicitly a Phase 2
/// "advanced" feature (docs/ROADMAP.md §8.5), not V1 scope.
///
/// Immutable: screens hold one as state and replace it wholesale via
/// [copyWith], the same pattern as the rest of the app's form state.
class TransactionFilter {
  const TransactionFilter({
    this.query = '',
    this.accountId,
    this.categoryId,
    this.types = const {},
    this.from,
    this.to,
  });

  /// Free-text search, matched against the description and the resolved
  /// account/destination-account/category names.
  final String query;

  /// Matches transactions where this account is either the source or, for a
  /// transfer, the destination.
  final String? accountId;

  final String? categoryId;

  /// Empty means "every type" — an empty filter set is not "match nothing".
  final Set<TransactionTypeFilter> types;

  /// Inclusive lower bound on the transaction's calendar date.
  final DateTime? from;

  /// Inclusive upper bound on the transaction's calendar date.
  final DateTime? to;

  bool get isActive =>
      query.trim().isNotEmpty ||
      accountId != null ||
      categoryId != null ||
      types.isNotEmpty ||
      from != null ||
      to != null;

  TransactionFilter copyWith({
    String? query,
    String? accountId,
    bool clearAccountId = false,
    String? categoryId,
    bool clearCategoryId = false,
    Set<TransactionTypeFilter>? types,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
  }) {
    return TransactionFilter(
      query: query ?? this.query,
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      types: types ?? this.types,
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
    );
  }

  /// Whether [row] satisfies every active criterion.
  ///
  /// [accountName] and [destinationAccountName] and [categoryName] are
  /// resolved by the caller — this stays a pure predicate with no database
  /// access, so it can run over an already-loaded list and be unit tested
  /// without a database.
  bool matches(
    TransactionRow row, {
    required String accountName,
    String? destinationAccountName,
    String? categoryName,
  }) {
    if (accountId != null &&
        row.accountId != accountId &&
        row.destinationAccountId != accountId) {
      return false;
    }
    if (categoryId != null && row.categoryId != categoryId) {
      return false;
    }
    if (types.isNotEmpty && !types.contains(typeFilterFor(row.type))) {
      return false;
    }
    if (from != null && row.date.isBefore(from!)) {
      return false;
    }
    if (to != null) {
      // `to` is an inclusive calendar day, so the exclusive bound is the
      // following midnight.
      final exclusiveTo = DateTime(to!.year, to!.month, to!.day + 1);
      if (!row.date.isBefore(exclusiveTo)) return false;
    }
    final trimmedQuery = query.trim().toLowerCase();
    if (trimmedQuery.isNotEmpty) {
      final haystack = [
        row.description,
        accountName,
        destinationAccountName ?? '',
        categoryName ?? '',
      ].join(' ').toLowerCase();
      if (!haystack.contains(trimmedQuery)) return false;
    }
    return true;
  }
}
