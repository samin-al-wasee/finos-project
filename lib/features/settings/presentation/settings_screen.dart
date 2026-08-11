import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/currencies.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../backup/presentation/backup_section.dart';
import '../../categories/presentation/categories_list_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../domain/app_settings.dart';
import '../domain/theme_preference.dart';

/// Settings screen (docs/ROADMAP.md §6.8, docs/UI_DESIGN.md §23).
///
/// Configuration only — no primary financial workflows live here. Sections that
/// are not implemented yet are shown disabled rather than hidden, so the shape of
/// the screen doesn't shift as features land.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Preferences fall back to defaults while loading, so this screen renders
    // immediately instead of flashing a spinner over a near-static list.
    final settings = ref
        .watch(appSettingsProvider)
        .maybeWhen(data: (value) => value, orElse: () => const AppSettings());

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: Text(themePreferenceLabel(settings.themePreference)),
            onTap: () => _pickTheme(context, ref, settings.themePreference),
          ),

          const _SectionHeader(title: 'Money'),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Default currency'),
            subtitle: Text(
              '${settings.defaultCurrency} — used when you create a new account',
            ),
            onTap: () => _pickCurrency(context, ref, settings.defaultCurrency),
          ),

          const _SectionHeader(title: 'Organisation'),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            subtitle: const Text('Add, edit, and archive categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CategoriesListScreen(),
              ),
            ),
          ),

          const _SectionHeader(title: 'Insights'),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('Reports'),
            subtitle: const Text('Income, expenses, and spending by category'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
            ),
          ),

          const _SectionHeader(title: 'Data'),
          const BackupSection(),

          const _SectionHeader(title: 'About'),
          const _AboutTile(),
        ],
      ),
    );
  }

  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref,
    ThemePreference current,
  ) async {
    final choice = await showDialog<ThemePreference>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final preference in ThemePreference.values)
            _ChoiceTile(
              label: themePreferenceLabel(preference),
              selected: preference == current,
              onTap: () => Navigator.of(context).pop(preference),
            ),
        ],
      ),
    );
    if (choice == null || choice == current || !context.mounted) return;

    await _save(
      context,
      () => ref.read(settingsControllerProvider).setThemePreference(choice),
      failureMessage: 'Could not save the theme',
    );
  }

  Future<void> _pickCurrency(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Default currency'),
        children: [
          for (final currency in supportedCurrencies)
            _ChoiceTile(
              label: '${currency.name} (${currency.symbol})',
              detail: currency.code,
              selected: currency.code == current,
              onTap: () => Navigator.of(context).pop(currency.code),
            ),
        ],
      ),
    );
    if (choice == null || choice == current || !context.mounted) return;

    await _save(
      context,
      () => ref.read(settingsControllerProvider).setDefaultCurrency(choice),
      failureMessage: 'Could not save the currency',
    );
  }

  /// Runs [action], reporting failure as a readable message (AGENTS.md §25).
  Future<void> _save(
    BuildContext context,
    Future<void> Function() action, {
    required String failureMessage,
  }) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    }
  }
}

/// One option inside a settings picker dialog.
///
/// The current choice is marked with both a check icon and a semantics
/// "selected" flag, so it does not rely on the icon alone.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: detail == null ? null : Text(detail!),
      trailing: selected ? const Icon(Icons.check) : null,
      selected: selected,
      onTap: onTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FinosColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: colors.mutedText),
      ),
    );
  }
}

/// Explains what the app is and where the data lives.
///
/// The local-first guarantee is the product's main privacy claim
/// (docs/REQUIREMENTS.md FR-09), so it is stated plainly rather than buried.
class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    return const ListTile(
      leading: Icon(Icons.info_outline),
      title: Text('FinOS'),
      subtitle: Text(
        'A personal finance tracker. Your financial data is stored only on '
        'this device — there is no account and nothing is uploaded.',
      ),
      isThreeLine: true,
    );
  }
}

/// User-facing label for a [ThemePreference].
String themePreferenceLabel(ThemePreference preference) {
  switch (preference) {
    case ThemePreference.system:
      return 'Match system';
    case ThemePreference.light:
      return 'Light';
    case ThemePreference.dark:
      return 'Dark';
  }
}
