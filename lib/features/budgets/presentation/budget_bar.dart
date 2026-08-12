import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/budget_progress.dart';

/// Maps derived budget health onto the semantic colour tokens.
///
/// Shared by the live budget card and budget history (docs/ROADMAP.md §8.3),
/// so a given health always reads the same colour everywhere it appears.
Color healthColor(FinosColors colors, BudgetHealth health) {
  switch (health) {
    case BudgetHealth.underLimit:
      return colors.success;
    case BudgetHealth.nearLimit:
      return colors.warning;
    case BudgetHealth.exceeded:
      return colors.error;
  }
}

/// Horizontal usage bar for a budget — its current period or a past one.
///
/// The fill is clamped at 100% so an exceeded budget stays inside its track; the
/// overflow is communicated by the health colour, an overflow marker, and the
/// "over budget" text beside it — never by colour alone (docs/UI_DESIGN.md §20).
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FinosColors>()!;
    final color = healthColor(colors, progress.health);

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: progress.usedFraction.clamp(0.0, 1.0),
              minHeight: AppSpacing.sm,
              backgroundColor: colors.border,
              color: color,
              // The percentage announced to screen readers is derived from the
              // clamped value, so it caps at 100; the amount and health text
              // beside the bar carry the overspend.
              semanticsLabel: '${progress.category.name} budget used',
            ),
          ),
        ),
        if (progress.isExceeded) ...[
          const SizedBox(width: AppSpacing.xs),
          // Mirrors the "██████████+" treatment in docs/UI_DESIGN.md §20.
          Text(
            '+',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ],
    );
  }
}
