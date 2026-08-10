import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../features/accounts/application/account_controller.dart';
import '../features/accounts/data/account_dao.dart';
import '../features/categories/application/category_controller.dart';
import '../features/categories/data/category_dao.dart';
import '../features/dashboard/domain/dashboard_data.dart';
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

/// Wraps a Drift watch stream with an "opening" timeout that only fires before
/// the first emission.
///
/// Drift's `watchAll()` emits once, then only re-emits on database changes, so
/// a plain `.timeout()` errors on any quiet-but-healthy stream — after 15 idle
/// seconds the app would claim the database is slow to open when it already
/// opened fine. The guard still surfaces a genuinely hung open (stuck
/// migration, no first emission) as a visible error, but lets an already-open
/// stream stay silent.
Stream<T> _guardOpenTimeout<T>(Stream<T> source) {
  var opened = false;
  return source
      .timeout(
        const Duration(seconds: 15),
        onTimeout: (sink) {
          if (!opened) {
            sink.addError(
              TimeoutException('Opening the database is taking too long'),
            );
          }
        },
      )
      .map((event) {
        opened = true;
        return event;
      });
}

/// Reactive stream of all accounts (for UI consumers).
final accountsStreamProvider = StreamProvider<List<FinancialAccountRow>>((ref) {
  return _guardOpenTimeout(ref.watch(accountDaoProvider).watchAll());
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
final categoriesStreamProvider = StreamProvider<List<CategoryRow>>((ref) {
  return _guardOpenTimeout(ref.watch(categoryDaoProvider).watchAll());
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
final transactionsStreamProvider = StreamProvider<List<TransactionRow>>((ref) {
  return _guardOpenTimeout(ref.watch(transactionDaoProvider).watchAll());
});

// ------------------------------------------------------------------
// Dashboard
// ------------------------------------------------------------------

/// Aggregated overview data for the Home tab (FR-07).
///
/// Watching `.future` on the account/transaction streams makes this provider
/// re-run on every stream emission, so the dashboard stays in sync with the
/// database. Balances are summed in minor units without currency conversion —
/// every account defaults to BDT in V1 (docs/DATA_MODEL.md §5).
final dashboardDataProvider = FutureProvider<DashboardData>((ref) async {
  final accounts = await ref.watch(accountsStreamProvider.future);
  final transactions = await ref.watch(transactionsStreamProvider.future);
  final dao = ref.watch(transactionDaoProvider);

  final now = DateTime.now();
  final totals = await dao.totalsForPeriod(
    DateTime(now.year, now.month),
    DateTime(now.year, now.month + 1),
  );

  final accountBalances = <AccountBalance>[
    for (final account in accounts)
      AccountBalance(
        account: account,
        balanceMinor:
            account.openingBalanceMinor +
            await dao.balanceImpactFor(account.id),
      ),
  ];

  final openingSum = accounts.fold(0, (sum, a) => sum + a.openingBalanceMinor);
  final totalBalanceMinor = openingSum + await dao.totalBalanceImpact();

  return DashboardData(
    totalBalanceMinor: totalBalanceMinor,
    incomeMinor: totals.incomeMinor,
    expenseMinor: totals.expenseMinor,
    accountBalances: accountBalances,
    recentTransactions: transactions.take(5).toList(),
  );
});
