// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credit_card_dao.dart';

// ignore_for_file: type=lint
mixin _$CreditCardDaoMixin on DatabaseAccessor<AppDatabase> {
  $FinancialAccountsTable get financialAccounts =>
      attachedDatabase.financialAccounts;
  $CreditCardDetailsTable get creditCardDetails =>
      attachedDatabase.creditCardDetails;
  CreditCardDaoManager get managers => CreditCardDaoManager(this);
}

class CreditCardDaoManager {
  final _$CreditCardDaoMixin _db;
  CreditCardDaoManager(this._db);
  $$FinancialAccountsTableTableManager get financialAccounts =>
      $$FinancialAccountsTableTableManager(
        _db.attachedDatabase,
        _db.financialAccounts,
      );
  $$CreditCardDetailsTableTableManager get creditCardDetails =>
      $$CreditCardDetailsTableTableManager(
        _db.attachedDatabase,
        _db.creditCardDetails,
      );
}
