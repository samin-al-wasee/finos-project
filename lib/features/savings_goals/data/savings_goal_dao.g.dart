// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'savings_goal_dao.dart';

// ignore_for_file: type=lint
mixin _$SavingsGoalDaoMixin on DatabaseAccessor<AppDatabase> {
  $FinancialAccountsTable get financialAccounts =>
      attachedDatabase.financialAccounts;
  $SavingsGoalsTable get savingsGoals => attachedDatabase.savingsGoals;
  SavingsGoalDaoManager get managers => SavingsGoalDaoManager(this);
}

class SavingsGoalDaoManager {
  final _$SavingsGoalDaoMixin _db;
  SavingsGoalDaoManager(this._db);
  $$FinancialAccountsTableTableManager get financialAccounts =>
      $$FinancialAccountsTableTableManager(
        _db.attachedDatabase,
        _db.financialAccounts,
      );
  $$SavingsGoalsTableTableManager get savingsGoals =>
      $$SavingsGoalsTableTableManager(_db.attachedDatabase, _db.savingsGoals);
}
