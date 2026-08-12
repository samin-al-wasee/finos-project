import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../accounts/presentation/account_type_label.dart';
import '../../budgets/domain/budget_progress.dart';
import '../../budgets/presentation/budget_bar.dart';
import '../../budgets/presentation/budget_details_screen.dart';
import '../../budgets/presentation/budget_labels.dart';
import '../../categories/presentation/category_icon.dart';
import '../domain/account_cash_flow.dart';
import '../domain/budget_performance.dart';
import '../domain/report_data.dart';
import '../domain/report_period.dart';

/// Financial reports screen (docs/ROADMAP.md §8.4).
///
/// Shows income vs expense for a selected period compared with the previous
/// equivalent period, and a full expense-by-category breakdown. Deliberately
/// scoped to fixed calendar periods (this/last month, this/last year) rather
/// than a custom date-range picker or per-account cash flow — those remain
/// future refinements, not this feature's V1.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.thisMonth;

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(reportDataProvider(_period));
    final categories = ref.watch(categoriesStreamProvider);
    final categoriesById = {
      for (final c in categories.valueOrNull ?? const <CategoryRow>[]) c.id: c,
    };
    final budgets = ref.watch(budgetProgressProvider);
    final budgetPerformance = budgetsForPerformanceReport(
      budgets.valueOrNull ?? const <BudgetProgress>[],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SegmentedButton<ReportPeriod>(
              segments: [
                for (final period in ReportPeriod.values)
                  ButtonSegment(
                    value: period,
                    label: Text(reportPeriodLabel(period)),
                  ),
              ],
              selected: {_period},
              showSelectedIcon: false,
              onSelectionChanged: (selected) =>
                  setState(() => _period = selected.single),
            ),
          ),
          Expanded(
            child: report.when(
              data: (data) => _ReportBody(
                data: data,
                period: _period,
                categoriesById: categoriesById,
                budgetPerformance: budgetPerformance,
              ),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Something went wrong',
                message: e.toString(),
                action: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(reportDataProvider(_period)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.data,
    required this.period,
    required this.categoriesById,
    required this.budgetPerformance,
  });

  final ReportData data;
  final ReportPeriod period;
  final Map<String, CategoryRow> categoriesById;
  final List<BudgetProgress> budgetPerformance;

  @override
  Widget build(BuildContext context) {
    if (data.totals.incomeMinor == 0 &&
        data.totals.expenseMinor == 0 &&
        data.categorySpending.isEmpty &&
        budgetPerformance.isEmpty) {
      return const EmptyState(
        icon: Icons.bar_chart_outlined,
        title: 'Nothing to report yet',
        message: 'No income or expenses were recorded in this period.',
      );
    }

    final comparisonLabel = reportComparisonLabel(period);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Income',
                amountMinor: data.totals.incomeMinor,
                percent: data.incomeChangePercent,
                comparisonLabel: comparisonLabel,
                increaseIsGood: true,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: _SummaryCard(
                label: 'Expenses',
                amountMinor: data.totals.expenseMinor,
                percent: data.expenseChangePercent,
                comparisonLabel: comparisonLabel,
                increaseIsGood: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _NetCashFlowCard(netMinor: data.totals.netCashFlowMinor),
        const SizedBox(height: AppSpacing.xl),
        if (data.categorySpending.isNotEmpty) ...[
          Text(
            'Spending by category',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final spending in data.categorySpending)
            _CategoryRow(
              spending: spending,
              category: categoriesById[spending.categoryId],
              totalExpenseMinor: data.totals.expenseMinor,
            ),
        ],
        if (budgetPerformance.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Budget Performance',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final progress in budgetPerformance)
            _BudgetPerformanceRow(progress: progress),
        ],
        if (data.accountCashFlows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Cash Flow by Account',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final flow in data.accountCashFlows)
            _AccountCashFlowRow(flow: flow),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// One income/expense summary card with a comparison line
/// (AGENTS.md §21 — the direction and magnitude are always spelled out in
/// text, never signalled by colour alone).
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amountMinor,
    required this.percent,
    required this.comparisonLabel,
    required this.increaseIsGood,
  });

  final String label;
  final int amountMinor;
  final double? percent;
  final String comparisonLabel;
  final bool increaseIsGood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              formatMinorUnits(amountMinor),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            _ComparisonLine(
              percent: percent,
              comparisonLabel: comparisonLabel,
              increaseIsGood: increaseIsGood,
              colors: colors,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NetCashFlowCard extends StatelessWidget {
  const _NetCashFlowCard({required this.netMinor});

  final int netMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Net', style: theme.textTheme.labelLarge),
            Text(
              formatMinorUnits(netMinor),
              style: theme.textTheme.titleLarge?.copyWith(
                color: netMinor >= 0 ? colors.income : colors.expense,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Expenses increased 12% vs previous month", coloured by whether that
/// direction is favourable — never by the sign alone.
class _ComparisonLine extends StatelessWidget {
  const _ComparisonLine({
    required this.percent,
    required this.comparisonLabel,
    required this.increaseIsGood,
    required this.colors,
    required this.style,
  });

  final double? percent;
  final String comparisonLabel;
  final bool increaseIsGood;
  final FinosColors colors;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final value = percent;
    if (value == null) {
      return Text(
        'No data for the previous period',
        style: style?.copyWith(color: colors.mutedText),
      );
    }

    final Color color;
    final String direction;
    if (value == 0) {
      color = colors.mutedText;
      direction = 'is unchanged';
    } else {
      final increased = value > 0;
      final favorable = increased == increaseIsGood;
      color = favorable ? colors.success : colors.error;
      direction = increased ? 'increased' : 'decreased';
    }

    final magnitude = value == 0 ? '' : ' ${value.abs().toStringAsFixed(0)}%';
    return Text(
      '$direction$magnitude $comparisonLabel',
      style: style?.copyWith(color: color, fontWeight: FontWeight.w600),
    );
  }
}

/// One row in the category breakdown — merged into a single screen-reader
/// announcement rather than separate stops for the icon, name, amount, and
/// bar (docs/UI_DESIGN.md §43).
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.spending,
    required this.category,
    required this.totalExpenseMinor,
  });

  final CategoryAmount spending;
  final CategoryRow? category;
  final int totalExpenseMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final share = totalExpenseMinor <= 0
        ? 0.0
        : spending.amountMinor / totalExpenseMinor;
    final name = category?.name ?? 'Uncategorized';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  categoryIcon(category?.icon ?? 'label'),
                  size: 18,
                  color: colors.mutedText,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  formatMinorUnits(spending.amountMinor),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.expense,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: share,
                minHeight: AppSpacing.sm,
                backgroundColor: colors.border,
                color: colors.expense,
                semanticsLabel: '$name spending',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the Budget Performance section — each budget shown for its own
/// current window rather than the report's selected period (see
/// `budgetsForPerformanceReport`). Reuses [BudgetBar] and the health label so
/// a budget's standing reads identically here and on the Budgets tab.
class _BudgetPerformanceRow extends StatelessWidget {
  const _BudgetPerformanceRow({required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final symbol = currencySymbol(progress.budget.currency);
    final spent = formatMinorUnits(progress.spentMinor, symbol: symbol);
    final limit = formatMinorUnits(progress.limitMinor, symbol: symbol);
    final remaining = progress.isExceeded
        ? '${formatMinorUnits(-progress.remainingMinor, symbol: symbol)} '
              'over budget'
        : '${formatMinorUnits(progress.remainingMinor, symbol: symbol)} '
              'remaining';

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BudgetDetailsScreen(budgetId: progress.budget.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    categoryIcon(progress.category.icon),
                    size: 18,
                    color: colors.mutedText,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          progress.category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          budgetWindowLabel(progress.window),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$spent / $limit',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              BudgetBar(progress: progress),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    budgetHealthLabel(progress.health),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: healthColor(colors, progress.health),
                    ),
                  ),
                  Text(remaining, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row in the Cash Flow by Account section — each account's net for the
/// selected period, plus its net for the previous period as plain text
/// rather than a percentage. Net cash flow is signed, and a period-over-
/// period percent change is undefined/misleading once the sign flips
/// between periods, so this deliberately doesn't reuse [_ComparisonLine]
/// (see docs/ROADMAP.md §8.4 and `accountCashFlowsForReport`).
class _AccountCashFlowRow extends StatelessWidget {
  const _AccountCashFlowRow({required this.flow});

  final AccountCashFlow flow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;
    final symbol = currencySymbol(flow.account.currency);
    final netMinor = flow.totals.netCashFlowMinor;
    final previousNetMinor = flow.previousTotals.netCashFlowMinor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: MergeSemantics(
        child: Row(
          children: [
            Icon(
              accountTypeIcon(flow.account.type),
              size: 18,
              color: colors.mutedText,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                flow.account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMinorUnits(netMinor, symbol: symbol),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: netMinor >= 0 ? colors.income : colors.expense,
                  ),
                ),
                Text(
                  'Last period: '
                  '${formatMinorUnits(previousNetMinor, symbol: symbol)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.mutedText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
