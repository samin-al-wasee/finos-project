import 'package:flutter/material.dart';

import '../features/accounts/presentation/accounts_list_screen.dart';
import '../features/budgets/presentation/budgets_list_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/loans/presentation/loans_list_screen.dart';
import '../features/quick_entry/presentation/quick_entry_bar.dart';
import '../features/transactions/presentation/transactions_list_screen.dart';

/// The root scaffold hosting the bottom navigation shell.
///
/// Hosts the primary destinations from docs/UI_DESIGN.md §12: Home,
/// Transactions, Accounts, Budgets, and Loans. Loans earns a tab rather than
/// hiding under Accounts because docs/UI_DESIGN.md §7 treats it as a top-level
/// financial area.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.swap_horiz_outlined),
      selectedIcon: Icon(Icons.swap_horiz),
      label: 'Transactions',
    ),
    NavigationDestination(
      icon: Icon(Icons.account_balance_wallet_outlined),
      selectedIcon: Icon(Icons.account_balance_wallet),
      label: 'Accounts',
    ),
    NavigationDestination(
      icon: Icon(Icons.pie_chart_outline),
      selectedIcon: Icon(Icons.pie_chart),
      label: 'Budgets',
    ),
    NavigationDestination(
      icon: Icon(Icons.handshake_outlined),
      selectedIcon: Icon(Icons.handshake),
      label: 'Loans',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Quick entry is hoisted here (rather than left inside individual tab
      // screens) so it's available from every tab, and so its per-keystroke
      // suggestion list is bounded by the layout's actual available height —
      // a plain Column child would report its unbounded intrinsic height and
      // overflow once that content plus a shown keyboard exceeds the screen.
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: const [
                  DashboardScreen(),
                  TransactionsListScreen(),
                  AccountsListScreen(),
                  BudgetsListScreen(),
                  LoansListScreen(),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: const QuickEntryBar(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: _destinations,
      ),
    );
  }
}
