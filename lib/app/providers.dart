import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../features/accounts/application/account_controller.dart';
import '../features/accounts/data/account_dao.dart';
import '../features/categories/application/category_controller.dart';
import '../features/categories/data/category_dao.dart';
import '../features/transactions/application/transaction_controller.dart';
import '../features/transactions/data/transaction_dao.dart';

/// The application database singleton.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.open();
  ref.onDispose(database.close);
  return database;
});

// ------------------------------------------------------------------
// Accounts
// ------------------------------------------------------------------

/// Data-access object for financial accounts.
final accountDaoProvider = Provider<AccountDao>((ref) {
  return AccountDao(ref.watch(appDatabaseProvider));
});

/// Application service for the account lifecycle.
final accountControllerProvider = Provider<AccountController>((ref) {
  return AccountController(ref.watch(accountDaoProvider));
});

/// Reactive stream of all accounts (for UI consumers).
///
/// A generous timeout converts a hung database-open (e.g. a stuck migration)
/// into a visible error instead of an infinite spinner.
final accountsStreamProvider = StreamProvider<List<FinancialAccountRow>>((ref) {
  return ref
      .watch(accountDaoProvider)
      .watchAll()
      .timeout(
        const Duration(seconds: 15),
        onTimeout: (sink) {
          sink.addError(
            TimeoutException('Opening the database is taking too long'),
          );
        },
      );
});

// ------------------------------------------------------------------
// Categories
// ------------------------------------------------------------------

/// Data-access object for categories.
final categoryDaoProvider = Provider<CategoryDao>((ref) {
  return CategoryDao(ref.watch(appDatabaseProvider));
});

/// Application service for the category lifecycle.
final categoryControllerProvider = Provider<CategoryController>((ref) {
  return CategoryController(ref.watch(categoryDaoProvider));
});

/// Reactive stream of all categories (for UI consumers), including archived
/// ones so management screens can render a restore section.
///
/// Same timeout rationale as [accountsStreamProvider].
final categoriesStreamProvider = StreamProvider<List<CategoryRow>>((ref) {
  return ref
      .watch(categoryDaoProvider)
      .watchAll()
      .timeout(
        const Duration(seconds: 15),
        onTimeout: (sink) {
          sink.addError(
            TimeoutException('Opening the database is taking too long'),
          );
        },
      );
});

// ------------------------------------------------------------------
// Transactions
// ------------------------------------------------------------------

/// Data-access object for transactions.
final transactionDaoProvider = Provider<TransactionDao>((ref) {
  return TransactionDao(ref.watch(appDatabaseProvider));
});

/// Application service for the transaction lifecycle.
final transactionControllerProvider = Provider<TransactionController>((ref) {
  return TransactionController(
    ref.watch(transactionDaoProvider),
    ref.watch(accountDaoProvider),
    ref.watch(categoryDaoProvider),
  );
});

/// Reactive stream of all transactions (for UI consumers).
///
/// Same timeout rationale as [accountsStreamProvider].
final transactionsStreamProvider = StreamProvider<List<TransactionRow>>((ref) {
  return ref
      .watch(transactionDaoProvider)
      .watchAll()
      .timeout(
        const Duration(seconds: 15),
        onTimeout: (sink) {
          sink.addError(
            TimeoutException('Opening the database is taking too long'),
          );
        },
      );
});
