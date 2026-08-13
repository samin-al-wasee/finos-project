import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../accounts/domain/account_status.dart';
import '../../accounts/presentation/account_form_screen.dart';
import '../../budgets/presentation/budget_form_screen.dart';
import '../../categories/domain/category_status.dart';
import '../../categories/domain/category_type.dart';
import '../../categories/presentation/category_form_screen.dart';
import '../../loans/domain/loan_draft.dart';
import '../../loans/presentation/loan_form_screen.dart';
import '../../loans/presentation/repayment_dialog.dart';
import '../../recurring/presentation/recurring_transaction_form_screen.dart';
import '../../templates/presentation/template_form_screen.dart';
import '../../transactions/presentation/transaction_form_screen.dart';
import '../application/quick_command_resolver.dart';
import '../domain/quick_command_parser.dart';
import '../domain/quick_command_spec.dart';
import '../domain/quick_field.dart';
import '../domain/quick_static_options.dart';

/// A terminal-style bar for recording any write operation the app supports
/// (docs/ARCHITECTURE.md, "quick entry") — the first typed word chooses what
/// (income, expense, a new account, a loan repayment, ...) and the rest fill
/// that operation's fields positionally. Typing `@` opens a filterable
/// suggestion list for whichever slot the cursor is in — the top-level list
/// of operations when no command is chosen yet, live account/category/loan
/// names, the fixed values a field like "period" accepts, or a date picker
/// for a date field.
///
/// Submitting never saves anything itself: it opens the exact screen (or
/// dialog) that operation already uses, pre-filled via a lightweight
/// `*Draft` value distinct from that screen's persisted `initial` row — the
/// same "review before saving" shape as using a template or a saved filter.
class QuickEntryBar extends ConsumerStatefulWidget {
  const QuickEntryBar({super.key});

  @override
  ConsumerState<QuickEntryBar> createState() => _QuickEntryBarState();
}

class _QuickEntryBarState extends ConsumerState<QuickEntryBar> {
  // The suggestion list's own cap, unchanged from before this fix.
  static const _maxSuggestionsHeight = 220.0;

  // A conservative upper bound on the input row's natural height (the
  // TextField + send button, plus their padding) at the default text scale —
  // reserved first so the suggestion list never claims space the input row
  // actually needs. Deliberately rounded up from the ~64px this row measures
  // at scale 1.0, since underestimating here is what causes the vertical
  // overflow this constant exists to prevent; the SingleChildScrollView in
  // build() covers the rest (e.g. a larger system text-scale setting).
  static const _minInputRowHeight = 72.0;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final accounts = (ref.watch(accountsStreamProvider).valueOrNull ?? [])
        .where((a) => a.status == AccountStatus.active)
        .toList();
    final categories = (ref.watch(categoriesStreamProvider).valueOrNull ?? [])
        .where((c) => c.status == CategoryStatus.active)
        .toList();
    final outstandingLoans = (ref.watch(loanProgressProvider).valueOrNull ?? [])
        .where((p) => !p.isPaid && !p.isArchived)
        .toList();

    final lookups = QuickEntryLookups(
      accounts: accounts,
      incomeCategories: categories
          .where((c) => c.type == CategoryType.income)
          .toList(),
      expenseCategories: categories
          .where((c) => c.type == CategoryType.expense)
          .toList(),
      anyCategories: categories,
      outstandingLoans: outstandingLoans,
    );

    final text = _controller.text;
    final parsed = parseQuickEntry(text);
    // Treats whatever's still being typed as committed, so the send button
    // and Enter-to-submit don't wait for a trailing space the user never
    // types before hitting send.
    final finalized = parseQuickEntry('$text ');
    final canSubmit =
        finalized.command != null && finalized.missingRequiredFields.isEmpty;

    final suggestions = _buildSuggestions(parsed, lookups);

    // Shown only on a fresh, untyped slot (right after the command word or a
    // trailing space) and gone the instant a character lands in that slot —
    // "income <amount>" fades as soon as the amount itself starts.
    final atFreshSlot = text.isEmpty || text.endsWith(' ');
    final ghostHint = (parsed.activeField != null && atFreshSlot)
        ? '<${parsed.activeField!.label.toLowerCase()}>'
        : null;
    final fieldStyle =
        theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    const fieldPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.md,
    );

    final inputRow = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (ghostHint != null)
                  // An invisible mirror of the typed text followed by
                  // the low-opacity hint, positioned exactly where
                  // the real TextField (same style/padding) would
                  // continue it — a ghost-text overlay, since
                  // InputDecoration.hintText disappears entirely the
                  // moment the field has any content.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Padding(
                        padding: fieldPadding,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              style: fieldStyle,
                              children: [
                                TextSpan(
                                  text: text,
                                  style: const TextStyle(
                                    color: Colors.transparent,
                                  ),
                                ),
                                TextSpan(
                                  text: ghostHint,
                                  style: TextStyle(
                                    color: theme
                                        .extension<FinosColors>()!
                                        .mutedText
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ),
                    ),
                  ),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: fieldStyle,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(lookups),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: fieldPadding,
                    hintText: parsed.command == null
                        ? 'Try @ — income, expense, transfer…'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            tooltip: 'Record',
            onPressed: canSubmit ? () => _submit(lookups) : null,
          ),
        ],
      ),
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A plain Flexible around the suggestion list still assumes the
            // *rest* of the Column (the input row) always gets its full,
            // unshrinkable natural height — a Column's non-flexible children
            // are laid out at their intrinsic size regardless of the
            // incoming constraint, so if the keyboard (or a larger system
            // text-scale setting, which grows the input row itself) leaves
            // less room than that alone, the Column overflows even with the
            // suggestion list's share reduced to nothing. Reserving the input
            // row's space first and handing only the remainder to the
            // suggestion list — capped at the same 220px as before — keeps
            // the common case pixel-identical to a plain ConstrainedBox(220)
            // while guaranteeing the total never exceeds what's available.
            final available = constraints.maxHeight;
            final suggestionsMaxHeight = available.isFinite
                ? (available - _minInputRowHeight).clamp(
                    0.0,
                    _maxSuggestionsHeight,
                  )
                : _maxSuggestionsHeight;

            // SingleChildScrollView is the last-resort net: if the input
            // row's *actual* height still exceeds the reserved estimate
            // (e.g. an even larger text scale than accounted for), this
            // turns that into a small scroll instead of a hard render
            // overflow — the dropdown clips/scrolls rather than showing the
            // overflow banner, on any screen size.
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (suggestions != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: suggestionsMaxHeight,
                      ),
                      child: suggestions,
                    ),
                  inputRow,
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Suggestions ──────────────────────────────────────────────────────────

  Widget? _buildSuggestions(
    ParsedQuickCommand parsed,
    QuickEntryLookups lookups,
  ) {
    final query = parsed.suggestionQuery;
    if (query == null) return null;

    if (parsed.command == null) {
      return _suggestionList([
        for (final spec in _topLevelCandidates(query))
          _SuggestionRow(
            title: spec.label,
            subtitle: spec.example,
            onTap: () => _applySuggestion(tokenIndex: 0, value: spec.label),
          ),
      ]);
    }

    final field = parsed.activeField;
    if (field == null) return null;

    if (field.kind == QuickFieldKind.date) {
      return _suggestionList([
        _SuggestionRow(
          title: 'Pick a date',
          icon: Icons.calendar_today,
          onTap: () => _pickDateForField(parsed.activeFieldIndex),
        ),
      ]);
    }

    if (field.kind != QuickFieldKind.select) return null;

    return _suggestionList([
      for (final candidate in _candidatesFor(field.source, lookups, query))
        _SuggestionRow(
          title: candidate.label,
          onTap: () => _applySuggestion(
            tokenIndex: parsed.activeFieldIndex + 1,
            value: candidate.value,
          ),
        ),
    ]);
  }

  Widget _suggestionList(List<_SuggestionRow> rows) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Text('No matches'),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final row in rows)
          ListTile(
            dense: true,
            leading: row.icon == null ? null : Icon(row.icon),
            title: Text(row.title),
            subtitle: row.subtitle == null ? null : Text(row.subtitle!),
            onTap: row.onTap,
          ),
      ],
    );
  }

  List<QuickCommandSpec> _topLevelCandidates(String query) {
    if (query.isEmpty) return quickCommandSpecs;
    final needle = query.toLowerCase();
    return quickCommandSpecs
        .where(
          (c) =>
              c.key.contains(needle) || c.label.toLowerCase().contains(needle),
        )
        .toList();
  }

  List<_Candidate> _candidatesFor(
    SuggestionSource source,
    QuickEntryLookups lookups,
    String query,
  ) {
    final List<_Candidate> all;
    switch (source) {
      case SuggestionSource.accounts:
        all = [for (final a in lookups.accounts) _Candidate(a.name, a.name)];
      case SuggestionSource.incomeCategories:
        all = [
          for (final c in lookups.incomeCategories) _Candidate(c.name, c.name),
        ];
      case SuggestionSource.expenseCategories:
        all = [
          for (final c in lookups.expenseCategories) _Candidate(c.name, c.name),
        ];
      case SuggestionSource.anyCategories:
        all = [
          for (final c in lookups.anyCategories) _Candidate(c.name, c.name),
        ];
      case SuggestionSource.outstandingLoans:
        all = [
          for (final l in lookups.outstandingLoans)
            _Candidate(
              l.loan.name,
              '${l.loan.name} · ${formatMinorUnits(l.outstandingMinor, symbol: currencySymbol(l.loan.currency))} left',
            ),
        ];
      case SuggestionSource.accountTypes:
        all = [
          for (final label in quickAccountTypeLabels.values)
            _Candidate(label, label),
        ];
      case SuggestionSource.categoryTypes:
        all = [
          for (final label in quickCategoryTypeLabels.values)
            _Candidate(label, label),
        ];
      case SuggestionSource.budgetPeriods:
        all = [
          for (final label in quickBudgetPeriodLabels.values)
            _Candidate(label, label),
        ];
      case SuggestionSource.presetTransactionTypes:
        all = [
          for (final label in quickPresetTransactionTypeLabels.values)
            _Candidate(label, label),
        ];
      case SuggestionSource.recurrenceFrequencies:
        all = [
          for (final label in quickRecurrenceFrequencyLabels.values)
            _Candidate(label, label),
        ];
      case SuggestionSource.topLevelCommands:
      case SuggestionSource.none:
        all = const [];
    }
    if (query.isEmpty) return all;
    final needle = query.toLowerCase();
    return all.where((c) => c.label.toLowerCase().contains(needle)).toList();
  }

  void _applySuggestion({required int tokenIndex, required String value}) {
    final newText = applyQuickEntrySuggestion(
      _controller.text,
      tokenIndex,
      value,
    );
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _pickDateForField(int activeFieldIndex) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 30),
    );
    if (picked == null || !mounted) return;
    final iso = picked.toIso8601String().split('T').first;
    _applySuggestion(tokenIndex: activeFieldIndex + 1, value: iso);
  }

  // ── Submit ───────────────────────────────────────────────────────────────

  Future<void> _submit(QuickEntryLookups lookups) async {
    final finalized = parseQuickEntry('${_controller.text} ');
    final command = finalized.command;
    if (command == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose what to record — try @ to see options'),
        ),
      );
      return;
    }

    QuickDispatch dispatch;
    try {
      dispatch = resolveQuickCommand(
        command: command,
        values: finalized.values,
        lookups: lookups,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(e))));
      return;
    }

    _controller.clear();
    await _dispatch(dispatch);
  }

  Future<void> _dispatch(QuickDispatch dispatch) async {
    switch (dispatch) {
      case DispatchTransactionForm(draft: final draft):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TransactionFormScreen(draft: draft),
          ),
        );
      case DispatchLoanForm(draft: final draft):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => LoanFormScreen(draft: draft)),
        );
      case DispatchAccountForm(draft: final draft):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AccountFormScreen(draft: draft),
          ),
        );
      case DispatchCategoryForm(draft: final draft):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CategoryFormScreen(draft: draft),
          ),
        );
      case DispatchBudgetForm(draft: final draft):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BudgetFormScreen(draft: draft),
          ),
        );
      case DispatchTemplateForm(draft: final draft):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TemplateFormScreen(draft: draft),
          ),
        );
      case DispatchRecurringForm(draft: final draft):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecurringTransactionFormScreen(draft: draft),
          ),
        );
      case DispatchRepaymentDialog(loanId: final loanId, draft: final draft):
        await _openRepaymentDialog(loanId, draft);
    }
  }

  /// Mirrors `LoanDetailsScreen._recordRepayment`: the repayment dialog needs
  /// a full [LoanProgress], not just an id, so it's fetched fresh here rather
  /// than routed to a screen.
  Future<void> _openRepaymentDialog(
    String loanId,
    RepaymentDraft? draft,
  ) async {
    final progress = await ref.read(loanProgressByIdProvider(loanId).future);
    if (progress == null || !mounted) return;

    final accounts = (ref.read(accountsStreamProvider).valueOrNull ?? [])
        .where((a) => a.status == AccountStatus.active)
        .toList();
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add an active account before recording a repayment'),
        ),
      );
      return;
    }

    final result = await RepaymentDialog.show(
      context,
      progress: progress,
      accounts: accounts,
      draft: draft,
    );
    if (result == null || !mounted) return;

    try {
      await ref
          .read(loanControllerProvider)
          .recordRepayment(
            loanId: loanId,
            amountMinor: result.amountMinor,
            accountId: result.accountId,
            date: result.date,
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Repayment recorded')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not record it: $e')));
      }
    }
  }

  String _errorMessage(Object e) => e is FormatException ? e.message : '$e';
}

class _Candidate {
  const _Candidate(this.value, this.label);
  final String value;
  final String label;
}

class _SuggestionRow {
  const _SuggestionRow({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onTap;
}
