// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'investment_dao.dart';

// ignore_for_file: type=lint
mixin _$InvestmentDaoMixin on DatabaseAccessor<AppDatabase> {
  $FinancialAccountsTable get financialAccounts =>
      attachedDatabase.financialAccounts;
  $InvestmentsTable get investments => attachedDatabase.investments;
  InvestmentDaoManager get managers => InvestmentDaoManager(this);
}

class InvestmentDaoManager {
  final _$InvestmentDaoMixin _db;
  InvestmentDaoManager(this._db);
  $$FinancialAccountsTableTableManager get financialAccounts =>
      $$FinancialAccountsTableTableManager(
        _db.attachedDatabase,
        _db.financialAccounts,
      );
  $$InvestmentsTableTableManager get investments =>
      $$InvestmentsTableTableManager(_db.attachedDatabase, _db.investments);
}
