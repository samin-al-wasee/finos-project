import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../investments/domain/investment_period_totals.dart';
import '../domain/period_totals.dart';
import '../domain/transaction_type.dart';
import 'transaction_table.dart';

part 'transaction_dao.g.dart';

/// The storage value for [type], taken from the same converter the schema uses.
///
/// Previously these queries spelled the value as `type.name.toUpperCase()`, which
/// happens to match for single-word types but silently produces `LOANRECEIPT`
/// instead of `LOAN_RECEIPT`. Going through the converter removes that whole class
/// of mismatch. The values are our own literals, so interpolating them carries no
/// injection risk.
String _storage(TransactionType type) =>
    const TransactionTypeConverter().toSql(type);

/// Data-access object for financial transactions.
///
/// Sits between the application layer and the Drift database; keeps UI and
/// domain code free of table/query details.
@DriftAccessor(tables: [Transactions])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  /// All transactions, newest first (streaming).
  ///
  /// Ordered by the financial event [Transactions.date] descending so recent
  /// activity surfaces at the top of the list.
  Stream<List<TransactionRow>> watchAll() => (select(
    transactions,
  )..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();

  /// All transactions, newest first (one-shot query).
  Future<List<TransactionRow>> getAll() =>
      (select(transactions)..orderBy([(t) => OrderingTerm.desc(t.date)])).get();

  /// Persists a new transaction row.
  Future<void> insertOne(TransactionsCompanion entry) =>
      into(transactions).insert(entry);

  /// Returns a single transaction by its [id], or `null` if not found.
  Future<TransactionRow?> getById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Replaces the entire row for an existing transaction.
  ///
  /// `replace` derives the WHERE clause from the row's primary key, so no
  /// explicit condition is needed.
  Future<void> updateOne(TransactionRow row) =>
      (update(transactions)).replace(row);

  /// Permanently deletes a transaction by [id].
  ///
  /// Actual transaction deletion may be allowed so users can correct accidental
  /// entries (docs/DATA_MODEL.md §47); this must update derived calculations.
  Future<void> deleteOne(String id) async {
    await (delete(transactions)..where((t) => t.id.equals(id))).go();
  }

  /// Net balance impact of every transaction touching [accountId].
  ///
  /// Income and incoming transfers add to the balance; expenses and outgoing
  /// transfers subtract from it. Loan receipts add and loan payments subtract:
  /// money genuinely moves through the account when a loan is made or repaid
  /// (ADR-004). Investment contributions subtract and investment payouts add,
  /// for the same reason (docs/adr/009-investment-accounting.md). Returns 0
  /// for an account with no transactions.
  ///
  /// This is a derived value (docs/DATA_MODEL.md §45) computed from the
  /// transaction table rather than stored alongside the account.
  Future<int> balanceImpactFor(String accountId) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(
        CASE
          WHEN type = '${_storage(TransactionType.income)}' THEN amount_minor
          WHEN type = '${_storage(TransactionType.expense)}' THEN -amount_minor
          WHEN type = '${_storage(TransactionType.transfer)}'
               AND account_id = ? THEN -amount_minor
          WHEN type = '${_storage(TransactionType.transfer)}'
               AND destination_account_id = ? THEN amount_minor
          WHEN type = '${_storage(TransactionType.loanReceipt)}' THEN amount_minor
          WHEN type = '${_storage(TransactionType.loanPayment)}' THEN -amount_minor
          WHEN type = '${_storage(TransactionType.investmentContribution)}'
               THEN -amount_minor
          WHEN type = '${_storage(TransactionType.investmentPayout)}'
               THEN amount_minor
          WHEN type = '${_storage(TransactionType.investmentWithdrawal)}'
               THEN amount_minor
          ELSE 0
        END
      ), 0) AS impact
      FROM transactions
      WHERE account_id = ? OR destination_account_id = ?
      ''',
      variables: [
        Variable(accountId),
        Variable(accountId),
        Variable(accountId),
        Variable(accountId),
      ],
    ).getSingle();

    return row.read<int>('impact');
  }

  /// Net balance impact of every transaction touching [accountId], dated
  /// strictly before [cutoffExclusive].
  ///
  /// Same CASE logic as [balanceImpactFor], scoped to a cutoff date so a
  /// credit card's balance as of its last statement close can be recovered —
  /// the figure a payment due date applies to (docs/DATA_MODEL.md §60).
  Future<int> balanceImpactForBefore(
    String accountId,
    DateTime cutoffExclusive,
  ) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(
        CASE
          WHEN type = '${_storage(TransactionType.income)}' THEN amount_minor
          WHEN type = '${_storage(TransactionType.expense)}' THEN -amount_minor
          WHEN type = '${_storage(TransactionType.transfer)}'
               AND account_id = ? THEN -amount_minor
          WHEN type = '${_storage(TransactionType.transfer)}'
               AND destination_account_id = ? THEN amount_minor
          WHEN type = '${_storage(TransactionType.loanReceipt)}' THEN amount_minor
          WHEN type = '${_storage(TransactionType.loanPayment)}' THEN -amount_minor
          WHEN type = '${_storage(TransactionType.investmentContribution)}'
               THEN -amount_minor
          WHEN type = '${_storage(TransactionType.investmentPayout)}'
               THEN amount_minor
          WHEN type = '${_storage(TransactionType.investmentWithdrawal)}'
               THEN amount_minor
          ELSE 0
        END
      ), 0) AS impact
      FROM transactions
      WHERE (account_id = ? OR destination_account_id = ?) AND date < ?
      ''',
      variables: [
        Variable(accountId),
        Variable(accountId),
        Variable(accountId),
        Variable(accountId),
        Variable(cutoffExclusive),
      ],
    ).getSingle();

    return row.read<int>('impact');
  }

  /// Sums income and expense for transactions dated `from <= date < to`
  /// (half-open range).
  ///
  /// Only income and expense are counted, so transfers and loan movements are
  /// excluded by construction: a transfer moves money between the user's own
  /// accounts, and a loan movement is a balance-sheet event, not earning or
  /// spending (docs/DATA_MODEL.md §17, ADR-004).
  Future<PeriodTotals> totalsForPeriod(DateTime from, DateTime to) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(
        CASE WHEN type = '${_storage(TransactionType.income)}'
             THEN amount_minor ELSE 0 END
      ), 0) AS income,
      COALESCE(SUM(
        CASE WHEN type = '${_storage(TransactionType.expense)}'
             THEN amount_minor ELSE 0 END
      ), 0) AS expense
      FROM transactions
      WHERE date >= ? AND date < ?
      ''',
      variables: [Variable(from), Variable(to)],
    ).getSingle();

    return PeriodTotals(
      incomeMinor: row.read<int>('income'),
      expenseMinor: row.read<int>('expense'),
    );
  }

  /// Sums income and expense for [accountId] dated `from <= date < to`
  /// (half-open range).
  ///
  /// Same shape as [totalsForPeriod], scoped to one account — for the
  /// Account Cash Flow report (docs/ROADMAP.md §8.4). Transfers and loan
  /// movements are excluded for the same reason as [totalsForPeriod].
  Future<PeriodTotals> totalsForAccountAndPeriod(
    String accountId,
    DateTime from,
    DateTime to,
  ) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(
        CASE WHEN type = '${_storage(TransactionType.income)}'
             THEN amount_minor ELSE 0 END
      ), 0) AS income,
      COALESCE(SUM(
        CASE WHEN type = '${_storage(TransactionType.expense)}'
             THEN amount_minor ELSE 0 END
      ), 0) AS expense
      FROM transactions
      WHERE account_id = ? AND date >= ? AND date < ?
      ''',
      variables: [Variable(accountId), Variable(from), Variable(to)],
    ).getSingle();

    return PeriodTotals(
      incomeMinor: row.read<int>('income'),
      expenseMinor: row.read<int>('expense'),
    );
  }

  /// Sums expenses in [categoryId] dated `from <= date < to` (half-open range).
  ///
  /// This is the budget-consumption rule (docs/DATA_MODEL.md §24): only EXPENSE
  /// transactions count. Income is not spending, and transfers move the user's
  /// own money between accounts, so neither may consume a budget
  /// (docs/DATA_MODEL.md §17). Transfers additionally always carry a null
  /// category, so they cannot match a budget's category in the first place.
  ///
  /// Returns 0 when the category has no expenses in the range.
  Future<int> expenseTotalForCategory(
    String categoryId,
    DateTime from,
    DateTime to,
  ) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS spent
      FROM transactions
      WHERE type = '${_storage(TransactionType.expense)}'
        AND category_id = ?
        AND date >= ? AND date < ?
      ''',
      variables: [Variable(categoryId), Variable(from), Variable(to)],
    ).getSingle();

    return row.read<int>('spent');
  }

  /// Sums expenses across [categoryIds] dated `from <= date < to` (half-open
  /// range) — the multi-category generalisation of [expenseTotalForCategory]
  /// (docs/ROADMAP.md §8.3, docs/adr/007-flexible-budget-scope.md). One
  /// `IN (...)` query, not N calls to [expenseTotalForCategory] summed in
  /// Dart.
  ///
  /// Returns 0 when [categoryIds] is empty or none of them have expenses in
  /// the range.
  Future<int> expenseTotalForCategories(
    Iterable<String> categoryIds,
    DateTime from,
    DateTime to,
  ) async {
    final ids = categoryIds.toList();
    if (ids.isEmpty) return 0;

    final placeholders = List.filled(ids.length, '?').join(', ');
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS spent
      FROM transactions
      WHERE type = '${_storage(TransactionType.expense)}'
        AND category_id IN ($placeholders)
        AND date >= ? AND date < ?
      ''',
      variables: [
        for (final id in ids) Variable(id),
        Variable(from),
        Variable(to),
      ],
    ).getSingle();

    return row.read<int>('spent');
  }

  /// Sums uncategorised expenses (`category_id IS NULL`) dated
  /// `from <= date < to` — the catch-all scope
  /// (docs/adr/007-flexible-budget-scope.md).
  ///
  /// Returns 0 when there are no uncategorised expenses in the range.
  Future<int> expenseTotalUncategorized(DateTime from, DateTime to) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS spent
      FROM transactions
      WHERE type = '${_storage(TransactionType.expense)}'
        AND category_id IS NULL
        AND date >= ? AND date < ?
      ''',
      variables: [Variable(from), Variable(to)],
    ).getSingle();

    return row.read<int>('spent');
  }

  /// Sums every expense dated `from <= date < to`, regardless of category —
  /// the whole-account/whole-portfolio scope
  /// (docs/adr/007-flexible-budget-scope.md).
  ///
  /// Returns 0 when there are no expenses in the range.
  Future<int> expenseTotalAll(DateTime from, DateTime to) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS spent
      FROM transactions
      WHERE type = '${_storage(TransactionType.expense)}'
        AND date >= ? AND date < ?
      ''',
      variables: [Variable(from), Variable(to)],
    ).getSingle();

    return row.read<int>('spent');
  }

  /// Sums expenses grouped by category, dated `from <= date < to`.
  ///
  /// Mirrors [expenseTotalForCategory] but for every category at once, for the
  /// dashboard's spending-by-category view (FR-07). A `null` key holds expenses
  /// with no assigned category rather than dropping them from the total.
  Future<Map<String?, int>> expenseTotalsByCategory(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await customSelect(
      '''
      SELECT category_id AS categoryId, SUM(amount_minor) AS spent
      FROM transactions
      WHERE type = '${_storage(TransactionType.expense)}'
        AND date >= ? AND date < ?
      GROUP BY category_id
      ''',
      variables: [Variable(from), Variable(to)],
    ).get();

    return {
      for (final row in rows)
        row.read<String?>('categoryId'): row.read<int>('spent'),
    };
  }

  /// Sum of balance impact across all accounts.
  ///
  /// Transfers are omitted because they net to zero globally — the source loses
  /// exactly what the destination gains.
  ///
  /// Loan and investment movements are **not** omitted, and that asymmetry is
  /// the point: the other side of a loan or an investment is a person, bank,
  /// or the government, outside FinOS, so nothing cancels them out. Lending
  /// money (or contributing to a fixed-term investment) genuinely reduces the
  /// total the user holds, and a repayment (or an investment payout)
  /// genuinely increases it (ADR-004, docs/adr/009-investment-accounting.md).
  /// Leaving them out would quietly overstate the total by every rupee ever
  /// lent or locked away in an investment.
  ///
  /// Returns 0 for an empty table.
  Future<int> totalBalanceImpact() async {
    final row = await customSelect('''
      SELECT COALESCE(SUM(
        CASE
          WHEN type = '${_storage(TransactionType.income)}' THEN amount_minor
          WHEN type = '${_storage(TransactionType.expense)}' THEN -amount_minor
          WHEN type = '${_storage(TransactionType.loanReceipt)}' THEN amount_minor
          WHEN type = '${_storage(TransactionType.loanPayment)}' THEN -amount_minor
          WHEN type = '${_storage(TransactionType.investmentContribution)}'
               THEN -amount_minor
          WHEN type = '${_storage(TransactionType.investmentPayout)}'
               THEN amount_minor
          WHEN type = '${_storage(TransactionType.investmentWithdrawal)}'
               THEN amount_minor
          ELSE 0
        END
      ), 0) AS impact
      FROM transactions
      ''').getSingle();

    return row.read<int>('impact');
  }

  /// Sum of the loan movements of one [type] belonging to [loanId].
  ///
  /// Used to derive a loan's outstanding balance. Because origination and
  /// repayment always sit on opposite sides for a given loan, passing the
  /// repayment type returns exactly the repayments, with no risk of counting the
  /// origination movement (ADR-004).
  Future<int> loanMovementTotal(String loanId, TransactionType type) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS total
      FROM transactions
      WHERE loan_id = ? AND type = ?
      ''',
      variables: [Variable(loanId), Variable(_storage(type))],
    ).getSingle();

    return row.read<int>('total');
  }

  /// Every transaction belonging to [loanId], newest first.
  Future<List<TransactionRow>> forLoan(String loanId) {
    return (select(transactions)
          ..where((t) => t.loanId.equals(loanId))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }

  /// Whether [loanId] has any transaction of [type].
  Future<bool> hasLoanMovement(String loanId, TransactionType type) async {
    final rows =
        await (select(transactions)
              ..where((t) => t.loanId.equals(loanId) & t.type.equalsValue(type))
              ..limit(1))
            .get();
    return rows.isNotEmpty;
  }

  /// Deletes every transaction belonging to [loanId].
  ///
  /// Used when a loan is deleted outright; the caller is responsible for running
  /// this inside the same transaction as the loan's own deletion.
  Future<void> deleteForLoan(String loanId) async {
    await (delete(transactions)..where((t) => t.loanId.equals(loanId))).go();
  }

  /// Sum of the investment movements of one [type] belonging to [investmentId].
  ///
  /// Used to derive an investment's contributed/paid-out totals — the same
  /// role [loanMovementTotal] plays for a loan's outstanding balance
  /// (docs/adr/009-investment-accounting.md).
  Future<int> investmentMovementTotal(
    String investmentId,
    TransactionType type,
  ) async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS total
      FROM transactions
      WHERE investment_id = ? AND type = ?
      ''',
      variables: [Variable(investmentId), Variable(_storage(type))],
    ).getSingle();

    return row.read<int>('total');
  }

  /// Contribution, payout, and withdrawal totals for every investment with
  /// activity dated `from <= date < to`, keyed by investment id — the
  /// Investment Activity report section's query (docs/ROADMAP.md §8.4). One
  /// grouped query rather than N calls to [investmentMovementTotal], the same
  /// reasoning [expenseTotalsByCategory] already applies to categories.
  Future<Map<String, InvestmentPeriodTotals>> investmentTotalsByInvestment(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await customSelect(
      '''
      SELECT investment_id AS investmentId,
      COALESCE(SUM(
        CASE WHEN type = '${_storage(TransactionType.investmentContribution)}'
             THEN amount_minor ELSE 0 END
      ), 0) AS contributed,
      COALESCE(SUM(
        CASE WHEN type = '${_storage(TransactionType.investmentPayout)}'
             THEN amount_minor ELSE 0 END
      ), 0) AS paidOut,
      COALESCE(SUM(
        CASE WHEN type = '${_storage(TransactionType.investmentWithdrawal)}'
             THEN amount_minor ELSE 0 END
      ), 0) AS withdrawn
      FROM transactions
      WHERE investment_id IS NOT NULL AND date >= ? AND date < ?
      GROUP BY investment_id
      ''',
      variables: [Variable(from), Variable(to)],
    ).get();

    return {
      for (final row in rows)
        row.read<String>('investmentId'): InvestmentPeriodTotals(
          contributedMinor: row.read<int>('contributed'),
          payoutMinor: row.read<int>('paidOut'),
          withdrawnMinor: row.read<int>('withdrawn'),
        ),
    };
  }

  /// Every transaction belonging to [investmentId], newest first.
  Future<List<TransactionRow>> forInvestment(String investmentId) {
    return (select(transactions)
          ..where((t) => t.investmentId.equals(investmentId))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }

  /// Whether [investmentId] has any transaction of [type].
  Future<bool> hasInvestmentMovement(
    String investmentId,
    TransactionType type,
  ) async {
    final rows =
        await (select(transactions)
              ..where(
                (t) =>
                    t.investmentId.equals(investmentId) &
                    t.type.equalsValue(type),
              )
              ..limit(1))
            .get();
    return rows.isNotEmpty;
  }

  /// Deletes every transaction belonging to [investmentId].
  ///
  /// Used when an investment is deleted outright; the caller is responsible
  /// for running this inside the same transaction as the investment's own
  /// deletion.
  Future<void> deleteForInvestment(String investmentId) async {
    await (delete(
      transactions,
    )..where((t) => t.investmentId.equals(investmentId))).go();
  }
}
