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
    this.onDelete,
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

  /// Callback for deleting the transaction (with confirmation in the caller).
  final VoidCallback? onDelete;

  /// Optional trailing widget replacing the default signed amount.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final type = transaction.type;

    final isTransfer = type == TransactionType.transfer;
    final isLoan = isLoanTransaction(type);
    final isInvestment = isInvestmentTransaction(type);
    final isSavingsGoal = isSavingsGoalTransaction(type);

    // Loan, investment, and savings-goal movements carry a description
    // written by their own feature (e.g. "Lent to John" or "Contribution ·
    // 5-year Sanchayapatra"), so the title reads correctly without threading
    // those names through every caller of this tile.
    final String title;
    if (isTransfer) {
      title = 'Transfer · $accountName → $destinationAccountName';
    } else if (isLoan) {
      title = transaction.description.isEmpty
          ? 'Loan'
          : transaction.description;
    } else if (isInvestment) {
      title = transaction.description.isEmpty
          ? 'Investment'
          : transaction.description;
    } else if (isSavingsGoal) {
      title = transaction.description.isEmpty
          ? 'Savings Goal'
          : transaction.description;
    } else if (categoryName?.isNotEmpty ?? false) {
      title = categoryName!;
    } else {
      title = transaction.description.isEmpty
          ? 'Transaction'
          : transaction.description;
    }
    final subtitle = isTransfer ? null : accountName;

    final IconData leadingIcon;
    if (isTransfer) {
      leadingIcon = Icons.swap_horiz;
    } else if (isLoan) {
      leadingIcon = Icons.handshake_outlined;
    } else if (isInvestment) {
      leadingIcon = Icons.savings_outlined;
    } else if (isSavingsGoal) {
      leadingIcon = Icons.flag_outlined;
    } else {
      leadingIcon = categoryIcon(categoryIconKey ?? 'label');
    }

    final trailingAmount =
        trailing ?? _Amount(type: type, amountMinor: transaction.amountMinor);
    final trailingWidget = onDelete == null
        ? trailingAmount
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              trailingAmount,
              _MoreMenuButton(onEdit: onTap, onDelete: onDelete),
            ],
          );

    return ListTile(
      leading: CircleAvatar(child: Icon(leadingIcon)),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailingWidget,
      onTap: onTap,
    );
  }
}

/// The overflow menu on a transaction tile offering edit and delete.
class _MoreMenuButton extends StatelessWidget {
  const _MoreMenuButton({required this.onEdit, required this.onDelete});

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Transaction options',
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit?.call();
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        if (onEdit != null)
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
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
      // Loan movements are balance-sheet events, so they borrow the transfer
      // colour rather than the income/expense ones — but they do carry a sign,
      // because unlike a transfer they really do change the total the user holds
      // (ADR-004).
      case TransactionType.loanReceipt:
        sign = '+';
        color = colors.transfer;
      case TransactionType.loanPayment:
        sign = '-';
        color = colors.transfer;
      // Same reasoning as loan movements: a balance-sheet event with a real
      // sign, borrowing the transfer colour rather than income/expense's.
      case TransactionType.investmentContribution:
        sign = '-';
        color = colors.transfer;
      case TransactionType.investmentPayout:
        sign = '+';
        color = colors.transfer;
      case TransactionType.investmentWithdrawal:
        sign = '+';
        color = colors.transfer;
      case TransactionType.savingsContribution:
        sign = '-';
        color = colors.transfer;
      case TransactionType.savingsWithdrawal:
        sign = '+';
        color = colors.transfer;
    }

    return Text(
      '$sign${formatMinorUnits(amountMinor)}',
      style: theme.textTheme.titleSmall?.copyWith(color: color),
    );
  }
}
