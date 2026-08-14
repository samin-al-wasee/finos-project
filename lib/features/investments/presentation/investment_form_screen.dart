import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/date.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../accounts/domain/account_status.dart';
import '../../recurring/domain/recurrence_frequency.dart';
import '../application/investment_controller.dart';
import '../domain/investment_contribution_mode.dart';
import '../domain/investment_instrument_type.dart';
import '../domain/investment_payout_frequency.dart';

/// Add/edit form for a fixed-term investment (docs/adr/009-investment-accounting.md).
///
/// When editing, only the name can change: the instrument type, contribution
/// mode, amount, accounts, and dates are fixed at creation, the same as a
/// loan's principal and disbursement account — changing any of them would
/// leave already-recorded contributions/payouts describing an investment
/// that no longer exists.
class InvestmentFormScreen extends ConsumerStatefulWidget {
  const InvestmentFormScreen({super.key, this.initial});

  /// The investment being edited, or `null` when creating a new one.
  final InvestmentRow? initial;

  @override
  ConsumerState<InvestmentFormScreen> createState() =>
      _InvestmentFormScreenState();
}

class _InvestmentFormScreenState extends ConsumerState<InvestmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late InvestmentInstrumentType _instrumentType;
  late InvestmentContributionMode _contributionMode;
  String? _sourceAccountId;
  String? _payoutAccountId;
  late DateTime _startDate;
  late DateTime _maturityDate;
  InvestmentPayoutFrequency _payoutFrequency =
      const InvestmentPayoutFrequency.atMaturity();
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _amountController = TextEditingController(
      text: initial == null ? '' : minorUnitsToInput(initial.amountMinor),
    );
    _instrumentType = initial?.instrumentType ?? InvestmentInstrumentType.fdr;
    _contributionMode =
        initial?.contributionMode ?? InvestmentContributionMode.lumpSum;
    _sourceAccountId = initial?.sourceAccountId;
    _payoutAccountId = initial?.payoutAccountId;
    _startDate = initial?.startDate ?? DateTime.now();
    _maturityDate =
        initial?.maturityDate ?? DateTime.now().add(const Duration(days: 365));
    _payoutFrequency =
        initial?.payoutFrequency ??
        const InvestmentPayoutFrequency.atMaturity();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(investmentControllerProvider);
    final colors = Theme.of(context).extension<FinosColors>()!;

    final accounts = ref
        .watch(accountsStreamProvider)
        .maybeWhen(
          data: (rows) =>
              rows.where((a) => a.status == AccountStatus.active).toList(),
          orElse: () => <FinancialAccountRow>[],
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit investment' : 'Add investment'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // ── Name ────────────────────────────────────────────────────
              TextFormField(
                controller: _nameController,
                autofocus: !_isEditing,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. 5-year Sanchayapatra',
                  border: OutlineInputBorder(),
                ),
                validator: _validateName,
              ),

              // ── Instrument type ─────────────────────────────────────────
              if (!_isEditing) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<InvestmentInstrumentType>(
                  initialValue: _instrumentType,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final type in InvestmentInstrumentType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(investmentInstrumentTypeLabel(type)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _instrumentType = value;
                      // A sensible default per type — still overridable below.
                      _contributionMode = value == InvestmentInstrumentType.dps
                          ? InvestmentContributionMode.recurring
                          : InvestmentContributionMode.lumpSum;
                    });
                  },
                ),

                // ── Contribution mode ─────────────────────────────────────
                const SizedBox(height: AppSpacing.lg),
                SegmentedButton<InvestmentContributionMode>(
                  segments: [
                    for (final mode in InvestmentContributionMode.values)
                      ButtonSegment(
                        value: mode,
                        label: Text(investmentContributionModeLabel(mode)),
                      ),
                  ],
                  selected: {_contributionMode},
                  onSelectionChanged: (selection) =>
                      setState(() => _contributionMode = selection.first),
                ),
              ],

              // ── Amount ──────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _amountController,
                enabled: !_isEditing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      _contributionMode == InvestmentContributionMode.recurring
                      ? 'Monthly installment'
                      : 'Principal',
                  hintText: 'e.g. 20000',
                  border: const OutlineInputBorder(),
                  helperText: _isEditing
                      ? 'The amount is fixed once an investment is created'
                      : null,
                ),
                validator: _isEditing ? null : _validateAmount,
              ),

              // ── Accounts ────────────────────────────────────────────────
              if (!_isEditing) ...[
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _sourceAccountId,
                  decoration: const InputDecoration(
                    labelText: 'Contributions come from',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in accounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _sourceAccountId = value;
                    // Same account by default; still changeable below.
                    _payoutAccountId ??= value;
                  }),
                  validator: (value) =>
                      value == null ? 'Choose an account' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _payoutAccountId,
                  decoration: const InputDecoration(
                    labelText: 'Payouts go to',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in accounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _payoutAccountId = value),
                  validator: (value) =>
                      value == null ? 'Choose an account' : null,
                ),

                // ── Dates ─────────────────────────────────────────────────
                const SizedBox(height: AppSpacing.sm),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start date'),
                  trailing: Text(
                    formatDate(_startDate),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  onTap: _pickStartDate,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Maturity date'),
                  trailing: Text(
                    formatDate(_maturityDate),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  onTap: _pickMaturityDate,
                ),

                // ── Payout frequency ──────────────────────────────────────
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<InvestmentPayoutFrequency>(
                  initialValue: _payoutFrequency,
                  decoration: const InputDecoration(
                    labelText: 'Profit payout',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final frequency in _payoutFrequencyOptions)
                      DropdownMenuItem(
                        value: frequency,
                        child: Text(investmentPayoutFrequencyLabel(frequency)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _payoutFrequency = value);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _payoutFrequency.isAtMaturity
                      ? 'Everything — principal and any interest — is paid '
                            'out once, at maturity.'
                      : 'Profit is paid out periodically; the principal is '
                            'still returned at maturity.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.mutedText),
                ),
              ],

              // ── Save ────────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _saving ? null : () => _save(controller),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'Save changes' : 'Add investment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _payoutFrequencyOptions = [
    InvestmentPayoutFrequency.atMaturity(),
    InvestmentPayoutFrequency.periodic(RecurrenceFrequency.monthly),
    InvestmentPayoutFrequency.periodic(RecurrenceFrequency.quarterly),
    InvestmentPayoutFrequency.periodic(RecurrenceFrequency.yearly),
  ];

  // ── Validation ──────────────────────────────────────────────────────────

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter a name for this investment';
    if (name.length > 100) return 'Name must be 100 characters or fewer';
    return null;
  }

  String? _validateAmount(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter an amount';
    try {
      if (parseMinorUnits(input) <= 0) {
        return 'Amount must be greater than zero';
      }
    } on FormatException {
      return 'Enter a valid amount';
    }
    return null;
  }

  // ── Date pickers ────────────────────────────────────────────────────────

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 30),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (!_maturityDate.isAfter(_startDate)) {
          _maturityDate = _startDate.add(const Duration(days: 365));
        }
      });
    }
  }

  Future<void> _pickMaturityDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _maturityDate,
      firstDate: _startDate.add(const Duration(days: 1)),
      lastDate: DateTime(DateTime.now().year + 30),
    );
    if (picked != null) setState(() => _maturityDate = picked);
  }

  // ── Save ────────────────────────────────────────────────────────────────

  Future<void> _save(InvestmentController controller) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await controller.update(
          id: widget.initial!.id,
          name: _nameController.text,
        );
      } else {
        await controller.create(
          name: _nameController.text,
          instrumentType: _instrumentType,
          contributionMode: _contributionMode,
          amountMinor: parseMinorUnits(_amountController.text.trim()),
          sourceAccountId: _sourceAccountId!,
          payoutAccountId: _payoutAccountId!,
          startDate: _startDate,
          maturityDate: _maturityDate,
          payoutFrequency: _payoutFrequency,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the investment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
