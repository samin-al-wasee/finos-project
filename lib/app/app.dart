import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'app_shell.dart';

/// Root widget of the FinOS application.
///
/// Provides the Material theme (light + dark, following the system) and hosts
/// the app shell. State is injected via [ProviderScope] in [main].
class FinOSApp extends StatelessWidget {
  const FinOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}
