import '../../../core/database/app_database.dart';
import 'transaction_type.dart';

/// The type groupings a user can filter by (FR-02, docs/ROADMAP.md §6.2).
///
/// [loan] covers both [TransactionType.loanReceipt] and
/// [TransactionType.loanPayment]: to a user filtering their history, a loan
/// disbursement and a loan repayment are both "loan activity," not two
/// unrelated types. [investment] is the same grouping for
/// [TransactionType.investmentContribution],
/// [TransactionType.investmentPayout], and
/// [TransactionType.investmentWithdrawal] (docs/adr/009-investment-accounting.md,
/// docs/adr/010-investment-early-withdrawal.md).
enum TransactionTypeFilter { income, expense, transfer, loan, investment }

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
    case TransactionType.investmentContribution:
    case TransactionType.investmentPayout:
    case TransactionType.investmentWithdrawal:
      return TransactionTypeFilter.investment;
  }
}

/// Search and filter criteria for the transaction list (FR-02,
/// docs/ROADMAP.md §8.5 "advanced" search).
///
/// Every criterion is independent and combines with AND — "food transactions
/// between ৳500 and ৳2,000 in July" is `categoryId` + `minAmountMinor` /
/// `maxAmountMinor` + `from` / `to` together, not a separate compound query
/// type.
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
    this.minAmountMinor,
    this.maxAmountMinor,
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

  /// Inclusive lower bound on the transaction's amount, in minor units.
  final int? minAmountMinor;

  /// Inclusive upper bound on the transaction's amount, in minor units.
  final int? maxAmountMinor;

  bool get isActive =>
      query.trim().isNotEmpty ||
      accountId != null ||
      categoryId != null ||
      types.isNotEmpty ||
      from != null ||
      to != null ||
      minAmountMinor != null ||
      maxAmountMinor != null;

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
    int? minAmountMinor,
    bool clearMinAmount = false,
    int? maxAmountMinor,
    bool clearMaxAmount = false,
  }) {
    return TransactionFilter(
      query: query ?? this.query,
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      types: types ?? this.types,
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      minAmountMinor: clearMinAmount
          ? null
          : (minAmountMinor ?? this.minAmountMinor),
      maxAmountMinor: clearMaxAmount
          ? null
          : (maxAmountMinor ?? this.maxAmountMinor),
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
    if (minAmountMinor != null && row.amountMinor < minAmountMinor!) {
      return false;
    }
    if (maxAmountMinor != null && row.amountMinor > maxAmountMinor!) {
      return false;
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

  /// Serializes the structured (non-free-text) criteria for storage as a
  /// saved query (docs/ROADMAP.md §8.5).
  ///
  /// [query] is omitted deliberately: free-text search is typed continuously
  /// in the app bar, not a criterion someone configures in the filter sheet
  /// and would expect a saved query to reapply.
  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'categoryId': categoryId,
    'types': types.map((t) => t.name).toList(),
    'from': from?.toIso8601String(),
    'to': to?.toIso8601String(),
    'minAmountMinor': minAmountMinor,
    'maxAmountMinor': maxAmountMinor,
  };

  /// Inverse of [toJson]. `query` is always empty on the result.
  factory TransactionFilter.fromJson(Map<String, dynamic> json) {
    return TransactionFilter(
      accountId: json['accountId'] as String?,
      categoryId: json['categoryId'] as String?,
      types: {
        for (final name in (json['types'] as List<dynamic>? ?? const []))
          TransactionTypeFilter.values.byName(name as String),
      },
      from: json['from'] == null
          ? null
          : DateTime.parse(json['from'] as String),
      to: json['to'] == null ? null : DateTime.parse(json['to'] as String),
      minAmountMinor: json['minAmountMinor'] as int?,
      maxAmountMinor: json['maxAmountMinor'] as int?,
    );
  }
}
