import 'package:flutter/material.dart';

import '../core/widgets/empty_state.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';

/// The root scaffold hosting the bottom navigation shell.
///
/// Hosts the four primary destinations from docs/UI_DESIGN.md §12. The Home tab
/// renders [DashboardScreen]; the remaining tabs are placeholders until their
/// features land in later phases.
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          DashboardScreen(),
          _PlaceholderScreen(
            icon: Icons.swap_horiz,
            title: 'Transactions',
            message: 'Transactions are coming in Phase 1.',
          ),
          _PlaceholderScreen(
            icon: Icons.account_balance_wallet,
            title: 'Accounts',
            message: 'Account management is coming in Phase 1.',
          ),
          _PlaceholderScreen(
            icon: Icons.pie_chart,
            title: 'Budgets',
            message: 'Budgets are coming in Phase 2.',
          ),
        ],
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

/// A simple placeholder tab until the feature it represents is built.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EmptyState(icon: icon, title: title, message: message),
    );
  }
}
