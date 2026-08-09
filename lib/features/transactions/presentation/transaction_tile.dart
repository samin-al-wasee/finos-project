import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatting/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../categories/presentation/category_icon.dart';
import '../domain/transaction_type.dart';

/// A single row in the transaction list.
///
/// Shows the category icon (or a swap icon for transfers), a title that
/// distinguishes income/expense from transfers, the account, and the signed
/// amount coloured by direction (docs/UI_DESIGN.md §9).
///
/// Display names are resolved by the caller so this widget stays reusable (e.g.
/// for the dashboard) without owning data lookups.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.accountName,
    this.destinationAccountName,
    this.categoryName,
    this.categoryIconKey,
    this.onTap,
    this.trailing,
  });

  final TransactionRow transaction;

  /// Name of the source/primary account.
  final String accountName;

  /// Name of the destination account, for transfers.
  final String? destinationAccountName;

  /// Resolved category name (income/expense only).
  final String? categoryName;

  /// Resolved category icon key (income/expense only).
  final String? categoryIconKey;

  final VoidCallback? onTap;

  /// Optional trailing widget replacing the default signed amount.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final type = transaction.type;

    final isTransfer = type == TransactionType.transfer;
    final title = isTransfer
        ? 'Transfer · $accountName → $destinationAccountName'
        : (categoryName?.isNotEmpty ?? false)
            ? categoryName!
            : (transaction.description.isEmpty
                ? 'Transaction'
                : transaction.description);
    final subtitle = isTransfer ? null : accountName;

    final IconData leadingIcon;
    if (isTransfer) {
      leadingIcon = Icons.swap_horiz;
    } else {
      leadingIcon = categoryIcon(categoryIconKey ?? 'label');
    }

    return ListTile(
      leading: CircleAvatar(child: Icon(leadingIcon)),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? _Amount(type: type, amountMinor: transaction.amountMinor),
      onTap: onTap,
    );
  }
}

/// The signed amount, coloured by income/expense/transfer semantics.
class _Amount extends StatelessWidget {
  const _Amount({required this.type, required this.amountMinor});

  final TransactionType type;
  final int amountMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinosColors>()!;

    final String sign;
    final Color color;
    switch (type) {
      case TransactionType.income:
        sign = '+';
        color = colors.income;
      case TransactionType.expense:
        sign = '-';
        color = colors.expense;
      case TransactionType.transfer:
        sign = '';
        color = colors.transfer;
    }

    return Text(
      '$sign${formatMinorUnits(amountMinor)}',
      style: theme.textTheme.titleSmall?.copyWith(color: color),
    );
  }
}
