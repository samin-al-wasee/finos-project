import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../features/accounts/application/account_controller.dart';
import '../features/accounts/data/account_dao.dart';
import '../features/backup/application/backup_service.dart';
import '../features/backup/application/csv_export_service.dart';
import '../features/backup/data/backup_file_store.dart';
import '../features/budgets/application/budget_controller.dart';
import '../features/budgets/data/budget_dao.dart';
import '../features/budgets/domain/budget_period.dart';
import '../features/budgets/domain/budget_progress.dart';
import '../features/budgets/domain/budget_status.dart';
import '../features/categories/application/category_controller.dart';
import '../features/categories/data/category_dao.dart';
import '../features/dashboard/domain/dashboard_data.dart';
import '../features/loans/application/loan_controller.dart';
import '../features/loans/data/loan_dao.dart';
import '../features/loans/domain/loan_progress.dart';
import '../features/recurring/application/recurring_transaction_controller.dart';
import '../features/recurring/data/recurring_transaction_dao.dart';
import '../features/recurring/domain/due_occurrences.dart';
import '../features/recurring/domain/due_recurring_group.dart';
import '../features/recurring/domain/recurring_status.dart';
import '../features/reports/domain/report_data.dart';
import '../features/reports/domain/report_period.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/data/settings_dao.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/templates/application/template_controller.dart';
import '../features/templates/data/template_dao.dart';
import '../features/transactions/application/transaction_controller.dart';
import '../features/transactions/data/transaction_dao.dart';

/// The application database singleton.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.open();
  ref.onDispose(database.close);
  return database;
});

// ------------------------------------------------------------------
// Settings
// ------------------------------------------------------------------

/// Data-access object for user preferences.
final settingsDaoProvider = Provider<SettingsDao>((ref) {
  return SettingsDao(ref.watch(appDatabaseProvider));
});

/// Application service for reading and writing preferences.
final settingsControllerProvider = Provider<SettingsController>((ref) {
  return SettingsController(ref.watch(settingsDaoProvider));
});

/// Reactive user preferences, typed (docs/UI_DESIGN.md §23).
///
/// Deliberately *not* wrapped in [_guardOpenTimeout]: this is read while the root
/// widget builds, so a slow or failed open must degrade to defaults rather than
/// block the app from rendering. Screens that show financial data still surface
/// database errors through their own guarded providers.
final appSettingsProvider = StreamProvider<AppSettings>((ref) {
  return ref.watch(settingsDaoProvider).watchAll().map(AppSettings.fromRows);
});

// ------------------------------------------------------------------
// Backup
// ------------------------------------------------------------------

/// Moves backup files in and out of the app.
///
/// Overridden with a fake in tests, where plugin method channels are
/// unavailable.
final backupFileStoreProvider = Provider<BackupFileStore>((ref) {
  return const PlatformBackupFileStore();
});

/// Serialises, validates, and restores backups (FR-08).
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(appDatabaseProvider));
});

/// Builds a CSV export of every transaction (FR-08).
final csvExportServiceProvider = Provider<CsvExportService>((ref) {
  return CsvExportService(ref.watch(appDatabaseProvider));
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
// Budgets
// ------------------------------------------------------------------

/// Data-access object for budgets.
final budgetDaoProvider = Provider<BudgetDao>((ref) {
  return BudgetDao(ref.watch(appDatabaseProvider));
});

/// Application service for the budget lifecycle.
final budgetControllerProvider = Provider<BudgetController>((ref) {
  return BudgetController(
    ref.watch(budgetDaoProvider),
    ref.watch(categoryDaoProvider),
  );
});

/// Reactive stream of all budgets (for UI consumers), including archived ones so
/// management screens can render a restore section.
final budgetsStreamProvider = StreamProvider<List<BudgetRow>>((ref) {
  return _guardOpenTimeout(ref.watch(budgetDaoProvider).watchAll());
});

/// Budgets paired with the spending measured against them (FR-04).
///
/// Watching `.future` on the budget, transaction, and category streams makes
/// this provider re-run whenever any of them changes, so a newly recorded
/// expense immediately moves the matching progress bar. Spending is derived from
/// transactions on every read rather than stored on the budget
/// (docs/DATA_MODEL.md §45), which keeps the two from ever disagreeing.
///
/// Budgets whose category is missing are skipped rather than throwing; the
/// foreign key makes that unreachable in practice, but a budget list is not
/// worth crashing over.
final budgetProgressProvider = FutureProvider<List<BudgetProgress>>((
  ref,
) async {
  final budgets = await ref.watch(budgetsStreamProvider.future);
  final categories = await ref.watch(categoriesStreamProvider.future);
  await ref.watch(transactionsStreamProvider.future);
  final dao = ref.watch(transactionDaoProvider);

  final categoriesById = {for (final c in categories) c.id: c};
  final now = DateTime.now();

  final progress = <BudgetProgress>[];
  for (final budget in budgets) {
    final category = categoriesById[budget.categoryId];
    if (category == null) continue;

    final window = budgetWindow(
      budget.period,
      reference: now,
      startDate: budget.startDate,
      endDate: budget.endDate,
    );
    progress.add(
      BudgetProgress(
        budget: budget,
        category: category,
        window: window,
        spentMinor: await dao.expenseTotalForCategory(
          budget.categoryId,
          window.from,
          window.to,
        ),
      ),
    );
  }
  return progress;
});

/// How many past periods [budgetHistoryProvider] looks back.
const budgetHistoryLength = 6;

/// Past periods' spend vs limit for one budget, newest first
/// (docs/ROADMAP.md §8.3, budget history).
///
/// Reuses [BudgetProgress] rather than a dedicated history type: a window in
/// the past and the current window are the same shape — a budget, a window,
/// and what was spent in it — so the same derived health/remaining/fraction
/// getters apply unchanged.
///
/// Returns an empty list for a custom-period budget (no repeating window to
/// look back over) or once a window predates the budget's own start date.
final budgetHistoryProvider =
    FutureProvider.family<List<BudgetProgress>, String>((ref, budgetId) async {
      final budgets = await ref.watch(budgetsStreamProvider.future);
      final categories = await ref.watch(categoriesStreamProvider.future);
      await ref.watch(transactionsStreamProvider.future);
      final dao = ref.watch(transactionDaoProvider);

      BudgetRow? budget;
      for (final b in budgets) {
        if (b.id == budgetId) {
          budget = b;
          break;
        }
      }
      if (budget == null || budget.period == BudgetPeriod.custom) {
        return const [];
      }

      CategoryRow? category;
      for (final c in categories) {
        if (c.id == budget.categoryId) {
          category = c;
          break;
        }
      }
      if (category == null) return const [];

      final startDay = dayStart(budget.startDate);
      final now = DateTime.now();
      final history = <BudgetProgress>[];
      for (var offset = -1; offset >= -budgetHistoryLength; offset--) {
        final window = shiftedBudgetWindow(
          budget.period,
          reference: now,
          offset: offset,
        )!;
        // The whole window predates the budget's existence — stop, since every
        // earlier offset will too.
        if (!window.to.isAfter(startDay)) break;

        history.add(
          BudgetProgress(
            budget: budget,
            category: category,
            window: window,
            spentMinor: await dao.expenseTotalForCategory(
              budget.categoryId,
              window.from,
              window.to,
            ),
          ),
        );
      }
      return history;
    });

// ------------------------------------------------------------------
// Loans
// ------------------------------------------------------------------

/// Data-access object for loans.
final loanDaoProvider = Provider<LoanDao>((ref) {
  return LoanDao(ref.watch(appDatabaseProvider));
});

/// Application service for the loan lifecycle.
final loanControllerProvider = Provider<LoanController>((ref) {
  return LoanController(
    ref.watch(appDatabaseProvider),
    ref.watch(loanDaoProvider),
    ref.watch(transactionDaoProvider),
    ref.watch(accountDaoProvider),
  );
});

/// Reactive stream of all loans, including archived ones.
final loansStreamProvider = StreamProvider<List<LoanRow>>((ref) {
  return _guardOpenTimeout(ref.watch(loanDaoProvider).watchAll());
});

/// Loans paired with everything derived from their repayments (FR-06).
///
/// Watches the transaction stream as well as the loan stream, so recording a
/// repayment immediately updates the outstanding amount. Outstanding is derived
/// on every read rather than stored (ADR-004), so it cannot drift from the
/// transactions behind it.
final loanProgressProvider = FutureProvider<List<LoanProgress>>((ref) async {
  final loans = await ref.watch(loansStreamProvider.future);
  await ref.watch(transactionsStreamProvider.future);
  final controller = ref.watch(loanControllerProvider);

  final progress = <LoanProgress>[];
  for (final loan in loans) {
    progress.add(await controller.progressFor(loan));
  }
  return progress;
});

/// Derived figures for one loan, for the details screen.
final loanProgressByIdProvider = FutureProvider.family<LoanProgress?, String>((
  ref,
  loanId,
) async {
  final all = await ref.watch(loanProgressProvider.future);
  for (final entry in all) {
    if (entry.loan.id == loanId) return entry;
  }
  return null;
});

/// The transactions belonging to one loan, newest first.
final loanMovementsProvider =
    FutureProvider.family<List<TransactionRow>, String>((ref, loanId) async {
      await ref.watch(transactionsStreamProvider.future);
      return ref.watch(transactionDaoProvider).forLoan(loanId);
    });

// ------------------------------------------------------------------
// Reports
// ------------------------------------------------------------------

/// Aggregated data for one report period (docs/ROADMAP.md §8.4).
///
/// Watching `.future` on the transaction stream re-runs this on every change,
/// the same pattern as [dashboardDataProvider].
final reportDataProvider = FutureProvider.family<ReportData, ReportPeriod>((
  ref,
  period,
) async {
  await ref.watch(transactionsStreamProvider.future);
  final dao = ref.watch(transactionDaoProvider);

  final now = DateTime.now();
  final window = reportWindow(period, reference: now);
  final previousWindow = previousReportWindow(period, reference: now);

  final totals = await dao.totalsForPeriod(window.from, window.to);
  final previousTotals = await dao.totalsForPeriod(
    previousWindow.from,
    previousWindow.to,
  );
  final expenseByCategory = await dao.expenseTotalsByCategory(
    window.from,
    window.to,
  );

  final categorySpending =
      expenseByCategory.entries
          .map((e) => CategoryAmount(categoryId: e.key, amountMinor: e.value))
          .toList()
        ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

  return ReportData(
    totals: totals,
    previousTotals: previousTotals,
    categorySpending: categorySpending,
  );
});

// ------------------------------------------------------------------
// Balances
// ------------------------------------------------------------------

/// Live per-account balances (opening balance + net transaction impact),
/// keyed by account id.
///
/// The opening balance is captured when an account is created and never
/// changes, so screens that want "what does this account hold right now" must
/// add the cumulative effect of income, expense, and transfer transactions.
/// Watching `.future` on both streams keeps the map in sync with every change.
/// Sums are in minor units without currency conversion — every account
/// defaults to BDT in V1 (docs/DATA_MODEL.md §5).
final accountBalancesProvider = FutureProvider<Map<String, int>>((ref) async {
  final accounts = await ref.watch(accountsStreamProvider.future);
  await ref.watch(transactionsStreamProvider.future);
  final dao = ref.watch(transactionDaoProvider);
  return {
    for (final account in accounts)
      account.id:
          account.openingBalanceMinor + await dao.balanceImpactFor(account.id),
  };
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
  final periodStart = DateTime(now.year, now.month);
  final periodEnd = DateTime(now.year, now.month + 1);
  final totals = await dao.totalsForPeriod(periodStart, periodEnd);
  final expenseByCategory = await dao.expenseTotalsByCategory(
    periodStart,
    periodEnd,
  );

  final categorySpending =
      expenseByCategory.entries
          .map((e) => CategorySpending(categoryId: e.key, amountMinor: e.value))
          .toList()
        ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

  final activeBudgets = (await ref.watch(
    budgetProgressProvider.future,
  )).where((p) => p.budget.status == BudgetStatus.active).toList();
  final budgetStatus = activeBudgets.isEmpty
      ? null
      : BudgetStatusSummary(
          limitMinor: activeBudgets.fold(0, (sum, p) => sum + p.limitMinor),
          spentMinor: activeBudgets.fold(0, (sum, p) => sum + p.spentMinor),
          budgetCount: activeBudgets.length,
          nearLimitCount: activeBudgets
              .where((p) => p.health == BudgetHealth.nearLimit)
              .length,
          exceededCount: activeBudgets
              .where((p) => p.health == BudgetHealth.exceeded)
              .length,
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
    categorySpending: categorySpending.take(5).toList(),
    budgetStatus: budgetStatus,
    recentTransactions: transactions.take(5).toList(),
  );
});

// ------------------------------------------------------------------
// Templates
// ------------------------------------------------------------------

/// Data-access object for transaction templates.
final templateDaoProvider = Provider<TemplateDao>((ref) {
  return TemplateDao(ref.watch(appDatabaseProvider));
});

/// Application service for the template lifecycle.
final templateControllerProvider = Provider<TemplateController>((ref) {
  return TemplateController(ref.watch(templateDaoProvider));
});

/// Reactive stream of all templates (for UI consumers).
final templatesStreamProvider = StreamProvider<List<TransactionTemplateRow>>((
  ref,
) {
  return _guardOpenTimeout(ref.watch(templateDaoProvider).watchAll());
});

// ------------------------------------------------------------------
// Recurring transactions
// ------------------------------------------------------------------

/// Data-access object for recurring transaction rules.
final recurringTransactionDaoProvider = Provider<RecurringTransactionDao>((
  ref,
) {
  return RecurringTransactionDao(ref.watch(appDatabaseProvider));
});

/// Application service for the recurring transaction lifecycle.
final recurringTransactionControllerProvider =
    Provider<RecurringTransactionController>((ref) {
      return RecurringTransactionController(
        ref.watch(appDatabaseProvider),
        ref.watch(recurringTransactionDaoProvider),
        ref.watch(transactionDaoProvider),
      );
    });

/// Reactive stream of all rules (for UI consumers), including archived ones.
final recurringTransactionsStreamProvider =
    StreamProvider<List<RecurringTransactionRow>>((ref) {
      return _guardOpenTimeout(
        ref.watch(recurringTransactionDaoProvider).watchAll(),
      );
    });

/// Every active rule with at least one occurrence due right now, for the
/// "confirm before creating" flow (docs/ROADMAP.md §8.1).
///
/// Watches the rules stream so confirming, skipping, or editing one refreshes
/// this immediately; re-evaluated against `DateTime.now()` on every rebuild,
/// which is what makes generation "check on app open" without any background
/// scheduling (docs/ARCHITECTURE.md §20).
final dueRecurringGroupsProvider = FutureProvider<List<DueRecurringGroup>>((
  ref,
) async {
  final rules = await ref.watch(recurringTransactionsStreamProvider.future);
  final now = DateTime.now();

  final groups = <DueRecurringGroup>[];
  for (final rule in rules) {
    if (rule.status != RecurringStatus.active) continue;
    final due = dueOccurrences(
      from: rule.nextOccurrence,
      frequency: rule.frequency,
      asOf: now,
      endDate: rule.endDate,
    );
    if (due.dates.isNotEmpty) {
      groups.add(DueRecurringGroup(rule: rule, due: due));
    }
  }
  return groups;
});
