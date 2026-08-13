import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/currencies.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../settings/domain/app_settings.dart';
import '../application/account_controller.dart';
import '../application/credit_card_controller.dart';
import '../domain/account_draft.dart';
import '../domain/account_type.dart';
import 'account_type_label.dart';

/// Add/edit form for a single account.
///
/// When [initial] is provided the form pre-fills and saves via update;
/// otherwise it creates a new account. The same widget powers both flows
/// (docs/UI_DESIGN.md §40). [draft] does the same for quick entry
/// (docs/ARCHITECTURE.md, "quick entry") — a one-off, unsaved seed, ignored
/// when [initial] is set.
///
/// Editing an existing credit-card account needs its billing details loaded
/// first, so this widget itself stays a thin wrapper: it resolves those
/// details (when relevant) before handing a fully-formed snapshot to
/// [_AccountFormBody], which owns the actual form state.
class AccountFormScreen extends ConsumerWidget {
  const AccountFormScreen({super.key, this.initial, this.draft});

  /// The account being edited, or `null` when creating a new one.
  final FinancialAccountRow? initial;

  /// A quick-entry seed to pre-fill a new account from, or `null`.
  final AccountDraft? draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = initial;
    if (account != null && account.type == AccountType.creditCard) {
      final details = ref.watch(creditCardDetailsProvider(account.id));
      return details.when(
        data: (row) => _AccountFormBody(
          initial: account,
          draft: draft,
          creditCardDetails: row,
        ),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, _) => Scaffold(
          appBar: AppBar(title: const Text('Edit account')),
          body: EmptyState(
            icon: Icons.error_outline,
            title: 'Something went wrong',
            message: error.toString(),
          ),
        ),
      );
    }
    return _AccountFormBody(initial: account, draft: draft);
  }
}

class _AccountFormBody extends ConsumerStatefulWidget {
  const _AccountFormBody({this.initial, this.draft, this.creditCardDetails});

  final FinancialAccountRow? initial;
  final AccountDraft? draft;

  /// The existing billing details when editing a credit-card account, or
  /// `null` for a new account (of any type) or a non-credit-card edit.
  final CreditCardDetailsRow? creditCardDetails;

  @override
  ConsumerState<_AccountFormBody> createState() => _AccountFormBodyState();
}

class _AccountFormBodyState extends ConsumerState<_AccountFormBody> {
  static const _defaultStatementDay = 1;
  static const _defaultPaymentDueOffsetDays = 21;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late final TextEditingController _creditLimitController;
  late final TextEditingController _paymentDueOffsetController;
  late AccountType _type;
  late String _currency;
  late int _statementDay;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;
  bool get _isCreditCard => _type == AccountType.creditCard;

  /// The account types selectable in this session: whether a credit-card
  /// account was created as one is fixed for its lifetime — same rule ADR-004
  /// applies to a loan's direction — so editing never offers to convert an
  /// account into or out of being a credit card.
  List<AccountType> get _selectableTypes {
    if (_isEditing) {
      return widget.initial!.type == AccountType.creditCard
          ? const [AccountType.creditCard]
          : [
              for (final type in AccountType.values)
                if (type != AccountType.creditCard) type,
            ];
    }
    return AccountType.values;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final draft = initial == null ? widget.draft : null;

    final presetBalanceMinor =
        initial?.openingBalanceMinor ?? draft?.openingBalanceMinor;
    _nameController = TextEditingController(
      text: initial?.name ?? draft?.name ?? '',
    );
    _balanceController = TextEditingController(
      text: presetBalanceMinor == null
          ? ''
          : minorUnitsToInput(presetBalanceMinor),
    );
    _type = initial?.type ?? draft?.type ?? AccountType.bank;
    // A new account starts on the currency chosen in Settings; an existing one
    // keeps its own, since changing it would reinterpret its stored balance.
    // The preference has always emitted by this point because the root widget
    // watches it, but fall back to the column default if it somehow hasn't.
    _currency =
        initial?.currency ??
        ref
            .read(appSettingsProvider)
            .maybeWhen(
              data: (settings) => settings.defaultCurrency,
              orElse: () => AppSettings.defaultCurrencyFallback,
            );

    final details = widget.creditCardDetails;
    _creditLimitController = TextEditingController(
      text: details == null ? '' : minorUnitsToInput(details.creditLimitMinor),
    );
    _paymentDueOffsetController = TextEditingController(
      text: (details?.paymentDueOffsetDays ?? _defaultPaymentDueOffsetDays)
          .toString(),
    );
    _statementDay = details?.statementDay ?? _defaultStatementDay;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _creditLimitController.dispose();
    _paymentDueOffsetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountController = ref.read(accountControllerProvider);
    final creditCardController = ref.read(creditCardControllerProvider);
    final selectableTypes = _selectableTypes;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit account' : 'Add account')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: !_isEditing,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  hintText: 'e.g. Main Bank',
                  border: OutlineInputBorder(),
                ),
                validator: _validateName,
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<AccountType>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Account type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final type in selectableTypes)
                    DropdownMenuItem(
                      value: type,
                      child: Text(accountTypeLabel(type)),
                    ),
                ],
                onChanged: selectableTypes.length > 1
                    ? (value) {
                        if (value != null) setState(() => _type = value);
                      }
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final currency in supportedCurrencies)
                    DropdownMenuItem(
                      value: currency.code,
                      child: Text('${currency.code} (${currency.symbol})'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _currency = value);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Opening balance',
                  hintText: 'e.g. 50,000.00',
                  prefixText: '${currencySymbol(_currency)} ',
                  border: const OutlineInputBorder(),
                ),
                validator: _validateBalance,
              ),
              if (_isCreditCard) ...[
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _creditLimitController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Credit limit',
                    hintText: 'e.g. 100,000.00',
                    prefixText: '${currencySymbol(_currency)} ',
                    border: const OutlineInputBorder(),
                  ),
                  validator: _validateCreditLimit,
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<int>(
                  initialValue: _statementDay,
                  decoration: const InputDecoration(
                    labelText: 'Statement closes on',
                    helperText: 'Day of the month; clamped to shorter months',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var day = 1; day <= 31; day++)
                      DropdownMenuItem(value: day, child: Text('Day $day')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _statementDay = value);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _paymentDueOffsetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Payment due',
                    hintText: 'e.g. 21',
                    suffixText: 'days after statement',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validatePaymentDueOffset,
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () => _save(accountController, creditCardController),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'Save changes' : 'Add account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter an account name';
    if (name.length > 100) return 'Name must be 100 characters or fewer';
    return null;
  }

  String? _validateBalance(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return null;
    try {
      parseMinorUnits(input);
    } on FormatException {
      return 'Enter a valid amount';
    }
    return null;
  }

  String? _validateCreditLimit(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter a credit limit';
    final int minor;
    try {
      minor = parseMinorUnits(input);
    } on FormatException {
      return 'Enter a valid amount';
    }
    if (minor <= 0) return 'Credit limit must be greater than zero';
    return null;
  }

  String? _validatePaymentDueOffset(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter how many days after the statement';
    final days = int.tryParse(input);
    if (days == null || days < 0) return 'Enter a whole number of days';
    return null;
  }

  Future<void> _save(
    AccountController accountController,
    CreditCardController creditCardController,
  ) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final name = _nameController.text.trim();
    final balanceInput = _balanceController.text.trim();
    final openingBalanceMinor = balanceInput.isEmpty
        ? 0
        : parseMinorUnits(balanceInput);

    try {
      if (_isCreditCard) {
        final creditLimitMinor = parseMinorUnits(
          _creditLimitController.text.trim(),
        );
        final paymentDueOffsetDays = int.parse(
          _paymentDueOffsetController.text.trim(),
        );
        if (_isEditing) {
          await creditCardController.update(
            accountId: widget.initial!.id,
            name: name,
            currency: _currency,
            openingBalanceMinor: openingBalanceMinor,
            creditLimitMinor: creditLimitMinor,
            statementDay: _statementDay,
            paymentDueOffsetDays: paymentDueOffsetDays,
          );
        } else {
          await creditCardController.create(
            name: name,
            currency: _currency,
            openingBalanceMinor: openingBalanceMinor,
            creditLimitMinor: creditLimitMinor,
            statementDay: _statementDay,
            paymentDueOffsetDays: paymentDueOffsetDays,
          );
        }
      } else if (_isEditing) {
        await accountController.update(
          id: widget.initial!.id,
          name: name,
          type: _type,
          currency: _currency,
          openingBalanceMinor: openingBalanceMinor,
        );
      } else {
        await accountController.create(
          name: name,
          type: _type,
          currency: _currency,
          openingBalanceMinor: openingBalanceMinor,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e, s) {
      debugPrint('[AccountForm] save error: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the account: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
