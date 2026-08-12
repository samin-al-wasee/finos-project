// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recurring_transaction_dao.dart';

// ignore_for_file: type=lint
mixin _$RecurringTransactionDaoMixin on DatabaseAccessor<AppDatabase> {
  $FinancialAccountsTable get financialAccounts =>
      attachedDatabase.financialAccounts;
  $CategoriesTable get categories => attachedDatabase.categories;
  $RecurringTransactionsTable get recurringTransactions =>
      attachedDatabase.recurringTransactions;
  RecurringTransactionDaoManager get managers =>
      RecurringTransactionDaoManager(this);
}

class RecurringTransactionDaoManager {
  final _$RecurringTransactionDaoMixin _db;
  RecurringTransactionDaoManager(this._db);
  $$FinancialAccountsTableTableManager get financialAccounts =>
      $$FinancialAccountsTableTableManager(
        _db.attachedDatabase,
        _db.financialAccounts,
      );
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$RecurringTransactionsTableTableManager get recurringTransactions =>
      $$RecurringTransactionsTableTableManager(
        _db.attachedDatabase,
        _db.recurringTransactions,
      );
}
