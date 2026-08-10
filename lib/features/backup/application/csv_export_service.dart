import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../transactions/domain/transaction_type.dart';

/// Builds a CSV export of every transaction (FR-08, docs/ARCHITECTURE.md §31).
///
/// Unlike the JSON backup, this is a one-way, human-readable export meant for
/// spreadsheets: account and category ids are resolved to their names, and
/// amounts are plain decimals rather than minor units. It is read-only and
/// cannot affect the database.
class CsvExportService {
  CsvExportService(this._database);

  final AppDatabase _database;

  static const _header = [
    'Date',
    'Type',
    'Account',
    'Destination Account',
    'Category',
    'Amount',
    'Currency',
    'Description',
  ];

  /// Suggested file name for an export, e.g. `finos-transactions-2026-08-10.csv`.
  static String fileNameFor(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'finos-transactions-${date.year}-$month-$day.csv';
  }

  /// Renders every transaction as CSV text, oldest first.
  Future<String> exportTransactions() async {
    final transactions = await (_database.select(
      _database.transactions,
    )..orderBy([(t) => OrderingTerm.asc(t.date)])).get();
    final accounts = await _database.select(_database.financialAccounts).get();
    final categories = await _database.select(_database.categories).get();

    final accountNames = {for (final a in accounts) a.id: a.name};
    final categoryNames = {for (final c in categories) c.id: c.name};

    final buffer = StringBuffer()..writeln(_row(_header));
    for (final transaction in transactions) {
      buffer.writeln(
        _row([
          _formatDate(transaction.date),
          _typeLabel(transaction.type),
          accountNames[transaction.accountId] ?? '',
          _lookup(accountNames, transaction.destinationAccountId),
          _lookup(categoryNames, transaction.categoryId),
          minorUnitsToInput(transaction.amountMinor),
          transaction.currency,
          transaction.description,
        ]),
      );
    }
    return buffer.toString();
  }

  static String _lookup(Map<String, String> names, String? id) =>
      id == null ? '' : (names[id] ?? '');

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String _typeLabel(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'Income';
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.transfer:
        return 'Transfer';
      case TransactionType.loanReceipt:
        return 'Loan Receipt';
      case TransactionType.loanPayment:
        return 'Loan Payment';
    }
  }

  /// Joins [fields] into one CSV line (RFC 4180), quoting a field only when it
  /// contains a comma, quote, or newline, and doubling any quotes inside it.
  static String _row(List<String> fields) => fields.map(_csvField).join(',');

  static String _csvField(String value) {
    if (!value.contains(RegExp(r'[,"\n\r]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
