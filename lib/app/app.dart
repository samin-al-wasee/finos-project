import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/domain/theme_preference.dart';
import 'app_shell.dart';
import 'providers.dart';

/// Root widget of the FinOS application.
///
/// Provides the Material theme (light + dark) and hosts the app shell. The theme
/// mode follows the user's stored preference; while preferences are loading — or
/// if they cannot be read — it falls back to the system setting so the app always
/// renders (docs/UI_DESIGN.md §23).
///
/// Wrapped in [DynamicColorBuilder] for Material You: on platforms that expose
/// a wallpaper-derived palette (Android 12+, including One UI), [AppTheme]
/// uses it instead of the fixed brand seed. `lightDynamic`/`darkDynamic` are
/// `null` on platforms without that capability (iOS, older Android), which
/// [AppTheme] treats as "use the fixed seed" — no platform branching needed
/// here.
class FinOSApp extends ConsumerWidget {
  const FinOSApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref
        .watch(appSettingsProvider)
        .maybeWhen(data: (value) => value, orElse: () => const AppSettings());

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: 'FinOS',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(lightDynamic),
          darkTheme: AppTheme.dark(darkDynamic),
          themeMode: themeModeFor(settings.themePreference),
          home: const AppShell(),
        );
      },
    );
  }
}
