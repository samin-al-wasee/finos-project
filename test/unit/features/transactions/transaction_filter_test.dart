import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/features/transactions/domain/transaction_filter.dart';
import 'package:finos_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for [TransactionFilter] — the predicate behind search and filter on
/// the transaction list (FR-02).
///
/// [TransactionFilter.matches] is a pure function over resolved names, so
/// these tests build [TransactionRow]s directly with no database.
void main() {
  TransactionRow row({
    String id = 'tx-1',
    TransactionType type = TransactionType.expense,
    int amountMinor = 1000,
    String accountId = 'acct-bank',
    String? destinationAccountId,
    String? categoryId,
    DateTime? date,
    String description = '',
  }) {
    return TransactionRow(
      id: id,
      type: type,
      amountMinor: amountMinor,
      currency: 'BDT',
      accountId: accountId,
      destinationAccountId: destinationAccountId,
      categoryId: categoryId,
      date: date ?? DateTime(2026, 8, 10),
      description: description,
      createdAt: DateTime(2026, 8, 10),
      updatedAt: DateTime(2026, 8, 10),
    );
  }

  group('isActive', () {
    test('is false for a default filter', () {
      expect(const TransactionFilter().isActive, isFalse);
    });

    test('is true when any single criterion is set', () {
      expect(const TransactionFilter(query: 'lunch').isActive, isTrue);
      expect(const TransactionFilter(accountId: 'a').isActive, isTrue);
      expect(const TransactionFilter(categoryId: 'c').isActive, isTrue);
      expect(
        TransactionFilter(types: {TransactionTypeFilter.income}).isActive,
        isTrue,
      );
      expect(TransactionFilter(from: DateTime(2026)).isActive, isTrue);
      expect(TransactionFilter(to: DateTime(2026)).isActive, isTrue);
      expect(const TransactionFilter(minAmountMinor: 500).isActive, isTrue);
      expect(const TransactionFilter(maxAmountMinor: 2000).isActive, isTrue);
    });

    test('a blank query does not count as active', () {
      expect(const TransactionFilter(query: '   ').isActive, isFalse);
    });
  });

  group('matches — text search', () {
    test('matches the description case-insensitively', () {
      const filter = TransactionFilter(query: 'GROCERIES');
      expect(
        filter.matches(
          row(description: 'Weekly groceries'),
          accountName: 'Main Bank',
        ),
        isTrue,
      );
      expect(
        filter.matches(row(description: 'Lunch'), accountName: 'Main Bank'),
        isFalse,
      );
    });

    test('matches the account name', () {
      const filter = TransactionFilter(query: 'bkash');
      expect(filter.matches(row(), accountName: 'bKash Wallet'), isTrue);
    });

    test('matches the destination account name for a transfer', () {
      const filter = TransactionFilter(query: 'savings');
      expect(
        filter.matches(
          row(type: TransactionType.transfer, destinationAccountId: 'acct-2'),
          accountName: 'Main Bank',
          destinationAccountName: 'Savings',
        ),
        isTrue,
      );
    });

    test('matches the category name', () {
      const filter = TransactionFilter(query: 'food');
      expect(
        filter.matches(
          row(categoryId: 'cat-food'),
          accountName: 'Main Bank',
          categoryName: 'Food',
        ),
        isTrue,
      );
    });

    test('an empty query matches everything', () {
      expect(
        const TransactionFilter().matches(row(), accountName: 'Main Bank'),
        isTrue,
      );
    });
  });

  group('matches — account', () {
    test('matches when the account is the source', () {
      const filter = TransactionFilter(accountId: 'acct-bank');
      expect(
        filter.matches(row(accountId: 'acct-bank'), accountName: 'Main Bank'),
        isTrue,
      );
    });

    test('matches when the account is the destination of a transfer', () {
      const filter = TransactionFilter(accountId: 'acct-cash');
      expect(
        filter.matches(
          row(
            type: TransactionType.transfer,
            accountId: 'acct-bank',
            destinationAccountId: 'acct-cash',
          ),
          accountName: 'Main Bank',
          destinationAccountName: 'Cash',
        ),
        isTrue,
      );
    });

    test('excludes a transaction on an unrelated account', () {
      const filter = TransactionFilter(accountId: 'acct-cash');
      expect(
        filter.matches(row(accountId: 'acct-bank'), accountName: 'Main Bank'),
        isFalse,
      );
    });
  });

  group('matches — category', () {
    test('matches the exact category', () {
      const filter = TransactionFilter(categoryId: 'cat-food');
      expect(
        filter.matches(
          row(categoryId: 'cat-food'),
          accountName: 'Main Bank',
          categoryName: 'Food',
        ),
        isTrue,
      );
    });

    test('excludes a different category, including uncategorized', () {
      const filter = TransactionFilter(categoryId: 'cat-food');
      expect(
        filter.matches(
          row(categoryId: 'cat-transport'),
          accountName: 'Main Bank',
        ),
        isFalse,
      );
      expect(
        filter.matches(row(categoryId: null), accountName: 'Main Bank'),
        isFalse,
      );
    });
  });

  group('matches — type', () {
    test('an empty type set matches every type', () {
      const filter = TransactionFilter();
      for (final type in TransactionType.values) {
        expect(
          filter.matches(row(type: type), accountName: 'Main Bank'),
          isTrue,
          reason: '$type should match an empty type filter',
        );
      }
    });

    test('groups loan receipt and loan payment under "loan"', () {
      final filter = TransactionFilter(types: {TransactionTypeFilter.loan});
      expect(
        filter.matches(
          row(type: TransactionType.loanReceipt),
          accountName: 'Main Bank',
        ),
        isTrue,
      );
      expect(
        filter.matches(
          row(type: TransactionType.loanPayment),
          accountName: 'Main Bank',
        ),
        isTrue,
      );
      expect(
        filter.matches(
          row(type: TransactionType.income),
          accountName: 'Main Bank',
        ),
        isFalse,
      );
    });

    test('multiple selected types are OR-ed together', () {
      final filter = TransactionFilter(
        types: {TransactionTypeFilter.income, TransactionTypeFilter.transfer},
      );
      expect(
        filter.matches(
          row(type: TransactionType.income),
          accountName: 'Main Bank',
        ),
        isTrue,
      );
      expect(
        filter.matches(
          row(type: TransactionType.transfer),
          accountName: 'Main Bank',
        ),
        isTrue,
      );
      expect(
        filter.matches(
          row(type: TransactionType.expense),
          accountName: 'Main Bank',
        ),
        isFalse,
      );
    });
  });

  group('matches — date range', () {
    test('includes both endpoints', () {
      final filter = TransactionFilter(
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 31),
      );
      expect(
        filter.matches(
          row(date: DateTime(2026, 8, 1)),
          accountName: 'Main Bank',
        ),
        isTrue,
      );
      expect(
        filter.matches(
          row(date: DateTime(2026, 8, 31)),
          accountName: 'Main Bank',
        ),
        isTrue,
      );
    });

    test('excludes dates outside the range', () {
      final filter = TransactionFilter(
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 31),
      );
      expect(
        filter.matches(
          row(date: DateTime(2026, 7, 31)),
          accountName: 'Main Bank',
        ),
        isFalse,
      );
      expect(
        filter.matches(
          row(date: DateTime(2026, 9, 1)),
          accountName: 'Main Bank',
        ),
        isFalse,
      );
    });

    test('an open-ended "from" only excludes earlier dates', () {
      final filter = TransactionFilter(from: DateTime(2026, 8, 1));
      expect(
        filter.matches(
          row(date: DateTime(2026, 12, 31)),
          accountName: 'Main Bank',
        ),
        isTrue,
      );
      expect(
        filter.matches(
          row(date: DateTime(2026, 7, 1)),
          accountName: 'Main Bank',
        ),
        isFalse,
      );
    });
  });

  group('matches — amount range', () {
    test('includes both endpoints', () {
      const filter = TransactionFilter(
        minAmountMinor: 500,
        maxAmountMinor: 2000,
      );
      expect(
        filter.matches(row(amountMinor: 500), accountName: 'Main Bank'),
        isTrue,
      );
      expect(
        filter.matches(row(amountMinor: 2000), accountName: 'Main Bank'),
        isTrue,
      );
    });

    test('excludes amounts outside the range', () {
      const filter = TransactionFilter(
        minAmountMinor: 500,
        maxAmountMinor: 2000,
      );
      expect(
        filter.matches(row(amountMinor: 499), accountName: 'Main Bank'),
        isFalse,
      );
      expect(
        filter.matches(row(amountMinor: 2001), accountName: 'Main Bank'),
        isFalse,
      );
    });

    test('an open-ended maximum only excludes smaller amounts', () {
      const filter = TransactionFilter(minAmountMinor: 500);
      expect(
        filter.matches(row(amountMinor: 1000000), accountName: 'Main Bank'),
        isTrue,
      );
      expect(
        filter.matches(row(amountMinor: 100), accountName: 'Main Bank'),
        isFalse,
      );
    });

    test('an open-ended minimum only excludes larger amounts', () {
      const filter = TransactionFilter(maxAmountMinor: 2000);
      expect(
        filter.matches(row(amountMinor: 100), accountName: 'Main Bank'),
        isTrue,
      );
      expect(
        filter.matches(row(amountMinor: 1000000), accountName: 'Main Bank'),
        isFalse,
      );
    });
  });

  group('matches — combined criteria', () {
    test('every active criterion must match', () {
      final filter = TransactionFilter(
        query: 'lunch',
        accountId: 'acct-bank',
        categoryId: 'cat-food',
        types: {TransactionTypeFilter.expense},
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 31),
      );
      final matching = row(
        accountId: 'acct-bank',
        categoryId: 'cat-food',
        type: TransactionType.expense,
        date: DateTime(2026, 8, 15),
        description: 'Lunch with a friend',
      );
      expect(
        filter.matches(
          matching,
          accountName: 'Main Bank',
          categoryName: 'Food',
        ),
        isTrue,
      );

      // Same row, but the wrong category — one mismatched criterion is enough.
      final wrongCategory = row(
        accountId: 'acct-bank',
        categoryId: 'cat-transport',
        type: TransactionType.expense,
        date: DateTime(2026, 8, 15),
        description: 'Lunch with a friend',
      );
      expect(
        filter.matches(
          wrongCategory,
          accountName: 'Main Bank',
          categoryName: 'Transport',
        ),
        isFalse,
      );
    });

    test(
      'the docs/ROADMAP.md §8.5 example: category + amount range + month',
      () {
        final filter = TransactionFilter(
          categoryId: 'cat-food',
          minAmountMinor: 50000, // ৳500
          maxAmountMinor: 200000, // ৳2,000
          from: DateTime(2026, 7),
          to: DateTime(2026, 7, 31),
        );

        expect(
          filter.matches(
            row(
              categoryId: 'cat-food',
              amountMinor: 80000,
              date: DateTime(2026, 7, 10),
            ),
            accountName: 'Main Bank',
            categoryName: 'Food',
          ),
          isTrue,
        );
        // Right category and date, but outside the amount range.
        expect(
          filter.matches(
            row(
              categoryId: 'cat-food',
              amountMinor: 300000,
              date: DateTime(2026, 7, 10),
            ),
            accountName: 'Main Bank',
            categoryName: 'Food',
          ),
          isFalse,
        );
        // Right category and amount, but outside the month.
        expect(
          filter.matches(
            row(
              categoryId: 'cat-food',
              amountMinor: 80000,
              date: DateTime(2026, 8, 1),
            ),
            accountName: 'Main Bank',
            categoryName: 'Food',
          ),
          isFalse,
        );
      },
    );
  });

  group('copyWith', () {
    test('clears a field only when its clear flag is set', () {
      const original = TransactionFilter(
        accountId: 'acct-bank',
        categoryId: 'cat-food',
      );

      final cleared = original.copyWith(clearAccountId: true);
      expect(cleared.accountId, isNull);
      expect(cleared.categoryId, 'cat-food');
    });

    test('clears the amount range independently of other fields', () {
      const original = TransactionFilter(
        categoryId: 'cat-food',
        minAmountMinor: 500,
        maxAmountMinor: 2000,
      );

      final cleared = original.copyWith(
        clearMinAmount: true,
        clearMaxAmount: true,
      );
      expect(cleared.minAmountMinor, isNull);
      expect(cleared.maxAmountMinor, isNull);
      expect(cleared.categoryId, 'cat-food');
    });

    test('replaces a field when a new value is given', () {
      const original = TransactionFilter(accountId: 'acct-bank');
      final updated = original.copyWith(accountId: 'acct-cash');
      expect(updated.accountId, 'acct-cash');
    });
  });
}
