// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template_dao.dart';

// ignore_for_file: type=lint
mixin _$TemplateDaoMixin on DatabaseAccessor<AppDatabase> {
  $FinancialAccountsTable get financialAccounts =>
      attachedDatabase.financialAccounts;
  $CategoriesTable get categories => attachedDatabase.categories;
  $TransactionTemplatesTable get transactionTemplates =>
      attachedDatabase.transactionTemplates;
  TemplateDaoManager get managers => TemplateDaoManager(this);
}

class TemplateDaoManager {
  final _$TemplateDaoMixin _db;
  TemplateDaoManager(this._db);
  $$FinancialAccountsTableTableManager get financialAccounts =>
      $$FinancialAccountsTableTableManager(
        _db.attachedDatabase,
        _db.financialAccounts,
      );
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$TransactionTemplatesTableTableManager get transactionTemplates =>
      $$TransactionTemplatesTableTableManager(
        _db.attachedDatabase,
        _db.transactionTemplates,
      );
}
