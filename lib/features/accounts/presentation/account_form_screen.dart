import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/currencies.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/account_controller.dart';
import '../domain/account_type.dart';
import 'account_type_label.dart';

/// Add/edit form for a single account.
///
/// When [initial] is provided the form pre-fills and saves via update;
/// otherwise it creates a new account. The same widget powers both flows
/// (docs/UI_DESIGN.md §40).
class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.initial});

  /// The account being edited, or `null` when creating a new one.
  final FinancialAccountRow? initial;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late AccountType _type;
  late String _currency;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _balanceController = TextEditingController(
      text: initial == null ? '' : _minorToInput(initial.openingBalanceMinor),
    );
    _type = initial?.type ?? AccountType.bank;
    _currency = initial?.currency ?? 'BDT';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(accountControllerProvider);

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
                  for (final type in AccountType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(accountTypeLabel(type)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
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
              const SizedBox(height: AppSpacing.xxl),
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

  Future<void> _save(AccountController controller) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final name = _nameController.text.trim();
    final balanceInput = _balanceController.text.trim();
    final openingBalanceMinor = balanceInput.isEmpty
        ? 0
        : parseMinorUnits(balanceInput);

    try {
      if (_isEditing) {
        await controller.update(
          id: widget.initial!.id,
          name: name,
          type: _type,
          currency: _currency,
          openingBalanceMinor: openingBalanceMinor,
        );
      } else {
        await controller.create(
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

/// Renders [minorUnits] as a plain decimal string for the balance input field
/// (no symbol or thousands separators), e.g. `5000050` → `'50000.50'`.
String _minorToInput(int minorUnits, {int decimals = 2}) {
  final pow = _pow10(decimals);
  final major = minorUnits ~/ pow;
  final fraction = (minorUnits % pow).toString().padLeft(decimals, '0');
  return fraction == '0' * decimals ? '$major' : '$major.$fraction';
}

int _pow10(int n) => n == 0 ? 1 : 10 * _pow10(n - 1);
