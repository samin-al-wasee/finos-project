import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A centered placeholder used to fill empty screens.
///
/// Composes an icon, a title, an optional descriptive [message] and an optional
/// [action]. Used across tabs that have no content yet (see docs/UI_DESIGN.md
/// §34 for the empty-state pattern).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    // A LayoutBuilder + scrollable, rather than a bare Center, so this still
    // renders identically (centered, no scrolling) whenever there's enough
    // room, but degrades to scrolling instead of a hard render overflow when
    // a caller squeezes this into less height than the content needs — e.g.
    // the app shell shrinking the current tab almost to nothing while the
    // quick entry bar's keyboard-open suggestion dropdown claims the rest of
    // the screen (docs/ARCHITECTURE.md, "quick entry").
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 56, color: colors.mutedText),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (message != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        message!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.mutedText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: AppSpacing.xl),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
