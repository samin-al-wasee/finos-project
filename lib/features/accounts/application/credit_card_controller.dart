import '../../../core/database/app_database.dart';
import '../../../core/utilities/ulid.dart';
import '../../transactions/data/transaction_dao.dart';
import '../data/credit_card_dao.dart';
import '../domain/account_type.dart';
import '../domain/credit_card_cycle.dart';
import 'account_controller.dart';

/// Application-service for a credit-card account's billing details
/// (docs/DATA_MODEL.md §60, ADR-005).
///
/// Wraps [AccountController] rather than duplicating account creation: a
/// credit-card account is a `financial_accounts` row like any other, plus one
/// `credit_card_details` row created in the same database transaction so
/// neither can exist without the other.
class CreditCardController {
  CreditCardController(
    this._database,
    this._accounts,
    this._details,
    this._transactions,
  );

  final AppDatabase _database;
  final AccountController _accounts;
  final CreditCardDao _details;
  final TransactionDao _transactions;

  /// Creates a credit-card account and its billing details together.
  ///
  /// Returns the generated account id.
  Future<String> create({
    required String name,
    required int creditLimitMinor,
    required int statementDay,
    required int paymentDueOffsetDays,
    String currency = 'BDT',
    int openingBalanceMinor = 0,
  }) async {
    _validate(
      creditLimitMinor: creditLimitMinor,
      statementDay: statementDay,
      paymentDueOffsetDays: paymentDueOffsetDays,
    );

    late final String accountId;
    // One transaction so an account can never be left without the billing
    // details that make it a credit card, or vice versa.
    await _database.transaction(() async {
      accountId = await _accounts.create(
        name: name,
        type: AccountType.creditCard,
        currency: currency,
        openingBalanceMinor: openingBalanceMinor,
      );
      await _details.insertOne(
        CreditCardDetailsCompanion.insert(
          id: generateId(),
          accountId: accountId,
          creditLimitMinor: creditLimitMinor,
          statementDay: statementDay,
          paymentDueOffsetDays: paymentDueOffsetDays,
        ),
      );
    });
    return accountId;
  }

  /// Updates a credit-card account's shared account fields and its billing
  /// details together.
  ///
  /// Throws [StateError] if [accountId] has no billing details.
  Future<void> update({
    required String accountId,
    required String name,
    required String currency,
    required int openingBalanceMinor,
    required int creditLimitMinor,
    required int statementDay,
    required int paymentDueOffsetDays,
  }) async {
    _validate(
      creditLimitMinor: creditLimitMinor,
      statementDay: statementDay,
      paymentDueOffsetDays: paymentDueOffsetDays,
    );

    final details = await _details.getByAccountId(accountId);
    if (details == null) {
      throw StateError('No credit card details for account: $accountId');
    }

    await _database.transaction(() async {
      await _accounts.update(
        id: accountId,
        name: name,
        type: AccountType.creditCard,
        currency: currency,
        openingBalanceMinor: openingBalanceMinor,
      );
      await _details.updateOne(
        details.copyWith(
          creditLimitMinor: creditLimitMinor,
          statementDay: statementDay,
          paymentDueOffsetDays: paymentDueOffsetDays,
          updatedAt: DateTime.now(),
        ),
      );
    });
  }

  /// Derives the current statement cycle for [account]'s credit card.
  ///
  /// Returns `null` if [account] has no billing details (i.e. it isn't
  /// actually a credit-card account, or its details haven't been created).
  /// [now] is injectable so tests are not tied to the clock (same idiom as
  /// a loan's overdue check).
  Future<CreditCardCycle?> cycleFor(
    FinancialAccountRow account, {
    DateTime? now,
  }) async {
    final details = await _details.getByAccountId(account.id);
    if (details == null) return null;

    final previousStatementDate = statementDateOnOrBefore(
      now ?? DateTime.now(),
      details.statementDay,
    );
    final currentImpact = await _transactions.balanceImpactFor(account.id);
    final previousImpact = await _transactions.balanceImpactForBefore(
      account.id,
      previousStatementDate,
    );

    return CreditCardCycle(
      details: details,
      currentBalanceMinor: account.openingBalanceMinor + currentImpact,
      previousStatementDate: previousStatementDate,
      previousStatementBalanceMinor:
          account.openingBalanceMinor + previousImpact,
    );
  }

  void _validate({
    required int creditLimitMinor,
    required int statementDay,
    required int paymentDueOffsetDays,
  }) {
    if (creditLimitMinor <= 0) {
      throw ArgumentError('Credit limit must be greater than zero');
    }
    if (statementDay < 1 || statementDay > 31) {
      throw ArgumentError('Statement day must be between 1 and 31');
    }
    if (paymentDueOffsetDays < 0) {
      throw ArgumentError('Payment due days cannot be negative');
    }
  }
}
