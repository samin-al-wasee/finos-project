import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/accounts/domain/account_status.dart';
import 'package:finos_app/features/accounts/domain/account_type.dart';
import 'package:finos_app/features/budgets/domain/budget_period.dart';
import 'package:finos_app/features/categories/domain/category_origin.dart';
import 'package:finos_app/features/categories/domain/category_status.dart';
import 'package:finos_app/features/categories/domain/category_type.dart';
import 'package:finos_app/features/loans/domain/loan_direction.dart';
import 'package:finos_app/features/loans/domain/loan_progress.dart';
import 'package:finos_app/features/loans/domain/loan_status.dart';
import 'package:finos_app/features/quick_entry/application/quick_command_resolver.dart';
import 'package:finos_app/features/quick_entry/domain/quick_command_spec.dart';
import 'package:finos_app/features/recurring/domain/recurrence_frequency.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [resolveQuickCommand] — turns a parsed command's raw string
/// values into a typed [QuickDispatch], resolving names against the lists in
/// [QuickEntryLookups] (docs/ARCHITECTURE.md, "quick entry").
void main() {
  final mainBank = FinancialAccountRow(
    id: 'acct-bank',
    name: 'Main Bank',
    type: AccountType.bank,
    currency: 'BDT',
    openingBalanceMinor: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    status: AccountStatus.active,
  );
  final cash = FinancialAccountRow(
    id: 'acct-cash',
    name: 'Cash',
    type: AccountType.cash,
    currency: 'BDT',
    openingBalanceMinor: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    status: AccountStatus.active,
  );
  final groceries = CategoryRow(
    id: 'cat-groceries',
    name: 'Groceries',
    type: CategoryType.expense,
    origin: CategoryOrigin.user,
    icon: 'label',
    status: CategoryStatus.active,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final salary = CategoryRow(
    id: 'cat-salary',
    name: 'Salary',
    type: CategoryType.income,
    origin: CategoryOrigin.user,
    icon: 'label',
    status: CategoryStatus.active,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final johnLoan = LoanProgress(
    loan: LoanRow(
      id: 'loan-1',
      type: LoanDirection.lent,
      name: 'John',
      principalMinor: 100000,
      currency: 'BDT',
      startDate: DateTime(2026, 1, 1),
      dueDate: null,
      description: '',
      disbursementAccountId: null,
      status: LoanStatus.active,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    repaidMinor: 0,
    repaymentCount: 0,
  );

  final lookups = QuickEntryLookups(
    accounts: [mainBank, cash],
    incomeCategories: [salary],
    expenseCategories: [groceries],
    anyCategories: [groceries, salary],
    outstandingLoans: [johnLoan],
  );

  QuickDispatch resolve(String commandKey, Map<String, String> values) {
    final command = findQuickCommandSpec(commandKey)!;
    return resolveQuickCommand(
      command: command,
      values: values,
      lookups: lookups,
    );
  }

  group('income / expense', () {
    test('resolves a full income command', () {
      final dispatch =
          resolve('income', {
                'amount': '50000',
                'date': '2026-08-01',
                'account': 'Main Bank',
                'category': 'Salary',
                'description': 'August pay',
              })
              as DispatchTransactionForm;

      expect(dispatch.draft.type, TransactionType.income);
      expect(dispatch.draft.amountMinor, 5000000);
      expect(dispatch.draft.date, DateTime(2026, 8, 1));
      expect(dispatch.draft.accountId, 'acct-bank');
      expect(dispatch.draft.categoryId, 'cat-salary');
      expect(dispatch.draft.description, 'August pay');
    });

    test('an income category must be an income category, not any name', () {
      expect(
        () => resolve('income', {
          'amount': '500',
          'account': 'Main Bank',
          'category': 'Groceries',
        }),
        throwsFormatException,
      );
    });

    test('category and date are optional', () {
      final dispatch =
          resolve('expense', {'amount': '500', 'account': 'Main Bank'})
              as DispatchTransactionForm;
      expect(dispatch.draft.categoryId, isNull);
      expect(dispatch.draft.date, isNull);
    });

    test('"today" resolves to a date', () {
      final dispatch =
          resolve('expense', {
                'amount': '500',
                'date': 'today',
                'account': 'Main Bank',
              })
              as DispatchTransactionForm;
      expect(dispatch.draft.date, isNotNull);
    });

    test('rejects an unparsable date', () {
      expect(
        () => resolve('expense', {
          'amount': '500',
          'date': 'sometime',
          'account': 'Main Bank',
        }),
        throwsFormatException,
      );
    });

    test('requires an account', () {
      expect(
        () => resolve('expense', {'amount': '500'}),
        throwsFormatException,
      );
    });

    test('rejects an unknown account name', () {
      expect(
        () => resolve('expense', {'amount': '500', 'account': 'Nonexistent'}),
        throwsFormatException,
      );
    });

    test('requires an amount', () {
      expect(
        () => resolve('expense', {'account': 'Main Bank'}),
        throwsFormatException,
      );
    });
  });

  group('transfer', () {
    test('resolves both accounts', () {
      final dispatch =
          resolve('transfer', {
                'amount': '1000',
                'account': 'Main Bank',
                'destinationAccount': 'Cash',
              })
              as DispatchTransactionForm;
      expect(dispatch.draft.type, TransactionType.transfer);
      expect(dispatch.draft.accountId, 'acct-bank');
      expect(dispatch.draft.destinationAccountId, 'acct-cash');
    });

    test('rejects the same account on both sides', () {
      expect(
        () => resolve('transfer', {
          'amount': '1000',
          'account': 'Main Bank',
          'destinationAccount': 'Main Bank',
        }),
        throwsFormatException,
      );
    });
  });

  group('lent / borrowed', () {
    test('resolves a new loan', () {
      final dispatch =
          resolve('lent', {
                'amount': '20000',
                'name': 'Alice',
                'account': 'Main Bank',
              })
              as DispatchLoanForm;
      expect(dispatch.draft.direction, LoanDirection.lent);
      expect(dispatch.draft.name, 'Alice');
      expect(dispatch.draft.principalMinor, 2000000);
      expect(dispatch.draft.disbursementAccountId, 'acct-bank');
    });

    test('the disbursement account is optional', () {
      final dispatch =
          resolve('borrowed', {'amount': '20000', 'name': 'Bank Loan'})
              as DispatchLoanForm;
      expect(dispatch.draft.disbursementAccountId, isNull);
    });

    test('requires a counterparty name', () {
      expect(() => resolve('lent', {'amount': '20000'}), throwsFormatException);
    });
  });

  group('repay', () {
    test('resolves the loan by name', () {
      final dispatch =
          resolve('repay', {'loan': 'John'}) as DispatchRepaymentDialog;
      expect(dispatch.loanId, 'loan-1');
      expect(dispatch.draft?.amountMinor, isNull);
    });

    test('amount, account, and date pre-fill the draft when given', () {
      final dispatch =
          resolve('repay', {
                'loan': 'John',
                'amount': '10000',
                'account': 'Main Bank',
                'date': '2026-08-05',
              })
              as DispatchRepaymentDialog;
      expect(dispatch.draft?.amountMinor, 1000000);
      expect(dispatch.draft?.accountId, 'acct-bank');
      expect(dispatch.draft?.date, DateTime(2026, 8, 5));
    });

    test('rejects an unrecognized loan name', () {
      expect(() => resolve('repay', {'loan': 'Nobody'}), throwsFormatException);
    });

    test('requires a loan', () {
      expect(() => resolve('repay', {}), throwsFormatException);
    });
  });

  group('account', () {
    test('resolves a new account with a typed account type', () {
      final dispatch =
          resolve('account', {'name': 'Savings', 'type': 'Cash'})
              as DispatchAccountForm;
      expect(dispatch.draft.name, 'Savings');
      expect(dispatch.draft.type, AccountType.cash);
    });

    test('defaults to Bank when the type is omitted', () {
      final dispatch =
          resolve('account', {'name': 'Savings'}) as DispatchAccountForm;
      expect(dispatch.draft.type, AccountType.bank);
    });

    test('rejects an unrecognized type', () {
      expect(
        () => resolve('account', {'name': 'Savings', 'type': 'Crypto'}),
        throwsFormatException,
      );
    });

    test('requires a name', () {
      expect(() => resolve('account', {}), throwsFormatException);
    });
  });

  group('category', () {
    test('resolves a new category', () {
      final dispatch =
          resolve('category', {'name': 'Fuel', 'type': 'Expense'})
              as DispatchCategoryForm;
      expect(dispatch.draft.name, 'Fuel');
      expect(dispatch.draft.type, CategoryType.expense);
    });
  });

  group('budget', () {
    test('resolves a new budget', () {
      final dispatch =
          resolve('budget', {
                'category': 'Groceries',
                'amount': '10000',
                'period': 'Weekly',
              })
              as DispatchBudgetForm;
      expect(dispatch.draft.categoryId, 'cat-groceries');
      expect(dispatch.draft.amountMinor, 1000000);
      expect(dispatch.draft.period, BudgetPeriod.weekly);
    });

    test('requires a category', () {
      expect(
        () => resolve('budget', {'amount': '10000'}),
        throwsFormatException,
      );
    });
  });

  group('template', () {
    test('resolves a new template, category from either type', () {
      final dispatch =
          resolve('template', {
                'name': 'Netflix',
                'type': 'Expense',
                'category': 'Salary',
              })
              as DispatchTemplateForm;
      expect(dispatch.draft.name, 'Netflix');
      // anyCategories includes both — 'Salary' resolves even for an expense
      // preset, since the resolver doesn't cross-check type against category.
      expect(dispatch.draft.categoryId, 'cat-salary');
    });
  });

  group('recurring', () {
    test('resolves a new recurring rule', () {
      final dispatch =
          resolve('recurring', {
                'name': 'Rent',
                'amount': '500000',
                'account': 'Main Bank',
                'frequency': 'Monthly',
              })
              as DispatchRecurringForm;
      expect(dispatch.draft.name, 'Rent');
      expect(dispatch.draft.amountMinor, 50000000);
      expect(dispatch.draft.accountId, 'acct-bank');
      expect(dispatch.draft.frequency, RecurrenceFrequency.monthly);
    });

    test('requires an account', () {
      expect(
        () => resolve('recurring', {'name': 'Rent', 'amount': '500000'}),
        throwsFormatException,
      );
    });
  });
}
