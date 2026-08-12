import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../templates/presentation/templates_list_screen.dart';
import '../domain/transaction_filter.dart';
import '../domain/transaction_type.dart';
import 'transaction_form_screen.dart';
import 'transaction_tile.dart';

/// Transactions tab content (FR-02).
///
/// Watches the transactions stream and groups rows into date sections
/// ("Today" / "Yesterday" / calendar date). A floating action button opens the
/// create form; per-tile popup menus offer edit and delete (with confirmation
/// — docs/UI_DESIGN.md §35). The AppBar's templates icon opens saved presets
/// for quick entry (docs/ROADMAP.md §8.2).
///
/// Search and filter (FR-02) run over the already-loaded list rather than a
/// database query: this is a local, single-user dataset, not a scale problem,
/// so a plain client-side predicate keeps the feature simple (AGENTS.md §22).
class TransactionsListScreen extends ConsumerStatefulWidget {
  const TransactionsListScreen({super.key});

  @override
  ConsumerState<TransactionsListScreen> createState() =>
      _TransactionsListScreenState();
}

class _TransactionsListScreenState
    extends ConsumerState<TransactionsListScreen> {
  final _searchController = TextEditingController();
  TransactionFilter _filter = const TransactionFilter();
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsStreamProvider);
    final accounts = ref.watch(accountsStreamProvider);
    final categories = ref.watch(categoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search transactions',
                  border: InputBorder.none,
                ),
                onChanged: (value) =>
                    setState(() => _filter = _filter.copyWith(query: value)),
              )
            : const Text('Transactions'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchController.clear();
                _filter = _filter.copyWith(query: '');
              }
            }),
          ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _hasStructuredFilter
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: 'Filter',
            onPressed: () => _openFilterSheet(
              context,
              accounts.valueOrNull ?? const [],
              categories.valueOrNull ?? const [],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bolt_outlined),
            tooltip: 'Templates',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TemplatesListScreen(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // The app shell keeps every tab alive in an IndexedStack, so all the tab
        // FABs share one route. Without distinct hero tags they collide and any
        // navigation from the shell throws.
        heroTag: 'fab-transactions',
        onPressed: () => _openForm(context),
        tooltip: 'Add transaction',
        child: const Icon(Icons.add),
      ),
      body: transactions.when(
        data: (rows) => rows.isEmpty
            ? const EmptyState(
                icon: Icons.swap_horiz,
                title: 'No transactions yet',
                message: 'Add your first transaction to start tracking money.',
                action: _AddTransactionButton(),
              )
            : accounts.when(
                data: (accountRows) => categories.when(
                  data: (categoryRows) => _buildFiltered(
                    rows: rows,
                    accounts: accountRows,
                    categories: categoryRows,
                  ),
                  error: (e, _) => _ErrorState(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(categoriesStreamProvider),
                  ),
                  loading: () => const _LoadingState(),
                ),
                error: (e, _) => _ErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(accountsStreamProvider),
                ),
                loading: () => const _LoadingState(),
              ),
        error: (e, _) => _ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(transactionsStreamProvider),
        ),
        loading: () => const _LoadingState(),
      ),
    );
  }

  /// Whether any filter beyond the search text is active — drives the filter
  /// icon's highlight, since the search field already shows its own state.
  bool get _hasStructuredFilter =>
      _filter.accountId != null ||
      _filter.categoryId != null ||
      _filter.types.isNotEmpty ||
      _filter.from != null ||
      _filter.to != null ||
      _filter.minAmountMinor != null ||
      _filter.maxAmountMinor != null;

  Widget _buildFiltered({
    required List<TransactionRow> rows,
    required List<FinancialAccountRow> accounts,
    required List<CategoryRow> categories,
  }) {
    final accountNames = {for (final a in accounts) a.id: a.name};
    final categoriesById = {for (final c in categories) c.id: c};

    final filtered = _filter.isActive
        ? rows
              .where(
                (row) => _filter.matches(
                  row,
                  accountName: accountNames[row.accountId] ?? row.accountId,
                  destinationAccountName: row.destinationAccountId == null
                      ? null
                      : accountNames[row.destinationAccountId],
                  categoryName: categoriesById[row.categoryId]?.name,
                ),
              )
              .toList()
        : rows;

    if (filtered.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No matching transactions',
        message: 'Try a different search or clear your filters.',
        action: OutlinedButton(
          onPressed: _clearFilters,
          child: const Text('Clear filters'),
        ),
      );
    }

    return Column(
      children: [
        if (_filter.isActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${filtered.length} of ${rows.length} transactions',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).extension<FinosColors>()!.mutedText,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _TransactionList(
            rows: filtered,
            accounts: accounts,
            categories: categories,
            onDelete: (row) => _confirmDelete(context, ref, row),
          ),
        ),
      ],
    );
  }

  void _clearFilters() {
    setState(() {
      _filter = const TransactionFilter();
      _searchController.clear();
      _searching = false;
    });
  }

  Future<void> _openFilterSheet(
    BuildContext context,
    List<FinancialAccountRow> accounts,
    List<CategoryRow> categories,
  ) async {
    final result = await showModalBottomSheet<TransactionFilter>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilterSheet(
        initial: _filter,
        accounts: accounts,
        categories: categories,
      ),
    );
    if (result != null) setState(() => _filter = result);
  }

  void _openForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TransactionFormScreen()),
    );
  }

  /// Asks for confirmation, then permanently deletes the transaction
  /// (docs/UI_DESIGN.md §35).
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TransactionRow row,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: const Text(
          'This permanently removes the transaction and its effect on '
          'your account balances.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final controller = ref.read(transactionControllerProvider);
    try {
      await controller.delete(row.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Transaction deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete the transaction: $e')),
        );
      }
    }
  }
}

/// Groups [rows] into date sections and renders one tile per transaction.
class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.rows,
    required this.accounts,
    required this.categories,
    required this.onDelete,
  });

  final List<TransactionRow> rows;
  final List<FinancialAccountRow> accounts;
  final List<CategoryRow> categories;

  /// Called when the user confirms deleting a transaction.
  final ValueChanged<TransactionRow> onDelete;

  @override
  Widget build(BuildContext context) {
    final accountNames = {for (final a in accounts) a.id: a.name};
    final categoriesById = {for (final c in categories) c.id: c};

    // Group by calendar day, preserving the newest-first order within and
    // across sections.
    final sections = <String, List<TransactionRow>>{};
    final order = <String>[];
    for (final row in rows) {
      final label = dateLabel(row.date);
      if (!sections.containsKey(label)) {
        sections[label] = [];
        order.add(label);
      }
      sections[label]!.add(row);
    }

    final children = <Widget>[];
    for (final label in order) {
      children.add(_SectionHeader(title: label));
      for (final row in sections[label]!) {
        final category = row.categoryId == null
            ? null
            : categoriesById[row.categoryId];
        // Loan movements are read-only here. Editing or deleting one directly
        // would let a loan's outstanding balance diverge from the transactions it
        // is derived from, so they are managed from the loan itself (ADR-004).
        final isLoan = isLoanTransaction(row.type);
        children.add(
          TransactionTile(
            key: ValueKey(row.id),
            transaction: row,
            accountName: accountNames[row.accountId] ?? row.accountId,
            destinationAccountName: row.destinationAccountId == null
                ? null
                : accountNames[row.destinationAccountId] ??
                      row.destinationAccountId,
            categoryName: category?.name,
            categoryIconKey: category?.icon,
            onTap: isLoan ? null : () => _openEdit(context, row),
            onDelete: isLoan ? null : () => onDelete(row),
          ),
        );
      }
    }

    // ListView.builder rather than ListView(children:): both lazily mount
    // elements via the same Sliver machinery, so this doesn't change what
    // gets rendered — it only defers constructing the off-screen tiles'
    // Widget objects, a minor saving as the list grows into the thousands.
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }

  void _openEdit(BuildContext context, TransactionRow row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionFormScreen(initial: row),
      ),
    );
  }
}

/// Modal sheet for setting the structured filters (account, category, type,
/// date range). The free-text search lives in the app bar instead, since it's
/// meant to be typed continuously rather than "applied".
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.accounts,
    required this.categories,
  });

  final TransactionFilter initial;
  final List<FinancialAccountRow> accounts;
  final List<CategoryRow> categories;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _accountId = widget.initial.accountId;
  late String? _categoryId = widget.initial.categoryId;
  final Set<TransactionTypeFilter> _types = {};
  DateTime? _from;
  DateTime? _to;
  late final TextEditingController _minAmountController;
  late final TextEditingController _maxAmountController;

  @override
  void initState() {
    super.initState();
    _types.addAll(widget.initial.types);
    _from = widget.initial.from;
    _to = widget.initial.to;
    _minAmountController = TextEditingController(
      text: widget.initial.minAmountMinor == null
          ? ''
          : minorUnitsToInput(widget.initial.minAmountMinor!),
    );
    _maxAmountController = TextEditingController(
      text: widget.initial.maxAmountMinor == null
          ? ''
          : minorUnitsToInput(widget.initial.maxAmountMinor!),
    );
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  /// Parses an amount field leniently: blank or unparsable text means "no
  /// bound" rather than blocking the Apply button — this is a filter, not a
  /// form that must validate before it can be submitted.
  int? _parseAmount(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return parseMinorUnits(text);
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter transactions', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String?>(
                initialValue: _accountId,
                decoration: const InputDecoration(
                  labelText: 'Account',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All accounts'),
                  ),
                  for (final a in widget.accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (value) => setState(() => _accountId = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All categories'),
                  ),
                  for (final c in widget.categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Type', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final type in TransactionTypeFilter.values)
                    FilterChip(
                      label: Text(_typeLabel(type)),
                      selected: _types.contains(type),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _types.add(type);
                        } else {
                          _types.remove(type);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Date range', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isFrom: true),
                      child: Text(_from == null ? 'From' : formatDate(_from!)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isFrom: false),
                      child: Text(_to == null ? 'To' : formatDate(_to!)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Amount range', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Min',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _maxAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Max',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(TransactionFilter(query: widget.initial.query)),
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final minAmount = _parseAmount(
                          _minAmountController.text,
                        );
                        final maxAmount = _parseAmount(
                          _maxAmountController.text,
                        );
                        Navigator.of(context).pop(
                          widget.initial.copyWith(
                            accountId: _accountId,
                            clearAccountId: _accountId == null,
                            categoryId: _categoryId,
                            clearCategoryId: _categoryId == null,
                            types: _types,
                            from: _from,
                            clearFrom: _from == null,
                            to: _to,
                            clearTo: _to == null,
                            minAmountMinor: minAmount,
                            clearMinAmount: minAmount == null,
                            maxAmountMinor: maxAmount,
                            clearMaxAmount: maxAmount == null,
                          ),
                        );
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  static String _typeLabel(TransactionTypeFilter type) {
    switch (type) {
      case TransactionTypeFilter.income:
        return 'Income';
      case TransactionTypeFilter.expense:
        return 'Expense';
      case TransactionTypeFilter.transfer:
        return 'Transfer';
      case TransactionTypeFilter.loan:
        return 'Loan';
    }
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

/// The button inside the empty state, kept as its own widget so the empty
/// state stays const.
class _AddTransactionButton extends StatelessWidget {
  const _AddTransactionButton();

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TransactionFormScreen()),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Add transaction'),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxxl),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      message: message,
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    );
  }
}
