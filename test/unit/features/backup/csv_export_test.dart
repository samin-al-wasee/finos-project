import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/data/account_dao.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/backup/application/csv_export_service.dart';
import 'package:finos_app/features/categories/data/category_dao.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/loans/application/loan_controller.dart';
import 'package:finos_app/features/loans/data/loan_dao.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/transactions/data/transaction_dao.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the CSV transaction export (FR-08, docs/ARCHITECTURE.md §31).
///
/// This export is read-only and human-readable, so the guarantees under test
/// are different from the JSON backup: every row must resolve account and
/// category names rather than ids, amounts must read as plain decimals, and a
/// description containing CSV-special characters must not corrupt the file.
void main() {
  late AppDatabase database;
  late AccountDao accounts;
  late CategoryDao categories;
  late TransactionDao transactions;
  late CsvExportService service;

  setUp(() {
    database = AppDatabase.inMemory();
    accounts = AccountDao(database);
    categories = CategoryDao(database);
    transactions = TransactionDao(database);
    service = CsvExportService(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<List<String>> exportLines() async {
    final csv = await service.exportTransactions();
    return csv.trim().split('\n');
  }

  test('an empty database exports just the header', () async {
    final lines = await exportLines();

    expect(lines, hasLength(1));
    expect(
      lines.single,
      'Date,Type,Account,Destination Account,Category,Amount,Currency,'
      'Description',
    );
  });

  test('resolves account and category names, oldest first', () async {
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await categories.insertOne(
      CategoriesCompanion.insert(
        id: 'cat-test-food',
        name: 'Food',
        type: CategoryType.expense,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-later',
        type: TransactionType.income,
        amountMinor: 10000000,
        accountId: 'acct-bank',
        date: DateTime(2026, 8, 5),
        description: const Value('Salary'),
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-earlier',
        type: TransactionType.expense,
        amountMinor: 150050,
        accountId: 'acct-bank',
        categoryId: const Value('cat-test-food'),
        date: DateTime(2026, 8, 1),
        description: const Value('Groceries'),
      ),
    );

    final lines = await exportLines();

    expect(lines, hasLength(3));
    // Oldest transaction first.
    expect(
      lines[1],
      '2026-08-01,Expense,Main Bank,,Food,1500.50,BDT,Groceries',
    );
    expect(lines[2], '2026-08-05,Income,Main Bank,,,100000,BDT,Salary');
  });

  test('a transfer shows both the source and destination account', () async {
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-cash',
        name: 'Cash',
        type: AccountType.cash,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-transfer',
        type: TransactionType.transfer,
        amountMinor: 500000,
        accountId: 'acct-bank',
        destinationAccountId: const Value('acct-cash'),
        date: DateTime(2026, 8, 5),
      ),
    );

    final lines = await exportLines();

    expect(lines[1], '2026-08-05,Transfer,Main Bank,Cash,,5000,BDT,');
  });

  test('a description with a comma and quotes is quoted safely', () async {
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    await transactions.insertOne(
      TransactionsCompanion.insert(
        id: 'tx-1',
        type: TransactionType.expense,
        amountMinor: 1000,
        accountId: 'acct-bank',
        date: DateTime(2026, 8, 1),
        description: const Value('Coffee, tea, and a "treat"'),
      ),
    );

    final lines = await exportLines();

    expect(
      lines[1],
      '2026-08-01,Expense,Main Bank,,,10,BDT,'
      '"Coffee, tea, and a ""treat"""',
    );
  });

  test('loan movements are labelled distinctly from income/expense', () async {
    await accounts.insertOne(
      FinancialAccountsCompanion.insert(
        id: 'acct-bank',
        name: 'Main Bank',
        type: AccountType.bank,
      ),
    );
    final loanController = LoanController(
      database,
      LoanDao(database),
      transactions,
      accounts,
    );
    await loanController.create(
      direction: LoanDirection.borrowed,
      name: 'Friend',
      principalMinor: 200000,
      disbursementAccountId: 'acct-bank',
      startDate: DateTime(2026, 8, 1),
    );

    final lines = await exportLines();

    expect(lines, hasLength(2));
    expect(lines[1], startsWith('2026-08-01,Loan Receipt,Main Bank,'));
  });
}
