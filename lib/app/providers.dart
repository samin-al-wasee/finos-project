import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../features/accounts/application/account_controller.dart';
import '../features/accounts/data/account_dao.dart';

/// The application database singleton.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.open();
  ref.onDispose(database.close);
  return database;
});

/// Data-access object for financial accounts.
final accountDaoProvider = Provider<AccountDao>((ref) {
  return AccountDao(ref.watch(appDatabaseProvider));
});

/// Application service for the account lifecycle.
final accountControllerProvider = Provider<AccountController>((ref) {
  return AccountController(ref.watch(accountDaoProvider));
});

/// Reactive stream of all accounts (for UI consumers).
final accountsStreamProvider = StreamProvider<List<FinancialAccountRow>>((ref) {
  return ref.watch(accountDaoProvider).watchAll();
});
