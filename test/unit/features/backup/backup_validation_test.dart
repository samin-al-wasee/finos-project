import 'dart:convert';

import 'package:finos_app/core/database/app_database.dart';
import 'package:finos_app/core/errors/app_exception.dart';
import 'package:finos_app/features/backup/application/backup_service.dart';
import 'package:finos_app/features/backup/domain/backup_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// Validation tests for importing a backup (AGENTS.md §14).
///
/// Every case here must be rejected with a [ValidationException] carrying a
/// message a user could act on — and must be rejected by `parse`, before any
/// database work begins.
void main() {
  late AppDatabase database;
  late BackupService service;

  setUp(() {
    database = AppDatabase.inMemory();
    service = BackupService(database);
  });

  tearDown(() async {
    await database.close();
  });

  /// A minimal valid document, optionally with fields overridden or removed.
  String document({
    Object? version = BackupFormat.version,
    bool includeVersion = true,
    List<Object?> accounts = const [],
    List<Object?> categories = const [],
    Object? transactions = const <Object?>[],
    Object? budgets = const <Object?>[],
  }) {
    return jsonEncode({
      if (includeVersion) BackupFormat.versionKey: version,
      BackupFormat.exportedAtKey: '2026-08-10T12:00:00.000',
      BackupFormat.accountsKey: accounts,
      BackupFormat.categoriesKey: categories,
      BackupFormat.transactionsKey: transactions,
      BackupFormat.budgetsKey: budgets,
    });
  }

  Map<String, Object?> account({
    String id = 'acct-1',
    Object? name = 'Bank',
    Object? type = 'BANK',
    Object? currency = 'BDT',
    Object? openingBalanceMinor = 0,
    Object? status = 'ACTIVE',
  }) {
    return {
      'id': id,
      'name': name,
      'type': type,
      'currency': currency,
      'opening_balance_minor': openingBalanceMinor,
      'status': status,
      'created_at': '2026-08-01T00:00:00.000',
      'updated_at': '2026-08-01T00:00:00.000',
    };
  }

  Map<String, Object?> category({
    String id = 'cat-1',
    Object? type = 'EXPENSE',
  }) {
    return {
      'id': id,
      'name': 'Food',
      'type': type,
      'origin': 'USER',
      'icon': 'label',
      'status': 'ACTIVE',
      'created_at': '2026-08-01T00:00:00.000',
      'updated_at': '2026-08-01T00:00:00.000',
    };
  }

  Map<String, Object?> transaction({
    String id = 'tx-1',
    Object? amountMinor = 1000,
    Object? accountId = 'acct-1',
    Object? categoryId,
    Object? destinationAccountId,
    Object? type = 'EXPENSE',
    Object? date = '2026-08-03T00:00:00.000',
  }) {
    return {
      'id': id,
      'type': type,
      'amount_minor': amountMinor,
      'currency': 'BDT',
      'account_id': accountId,
      'destination_account_id': destinationAccountId,
      'category_id': categoryId,
      'date': date,
      'description': '',
      'created_at': '2026-08-03T00:00:00.000',
      'updated_at': '2026-08-03T00:00:00.000',
    };
  }

  Map<String, Object?> budget({
    String id = 'budget-1',
    Object? categoryId = 'cat-1',
    Object? amountMinor = 1000,
    Object? period = 'MONTHLY',
  }) {
    return {
      'id': id,
      'category_id': categoryId,
      'amount_minor': amountMinor,
      'currency': 'BDT',
      'period': period,
      'start_date': '2026-08-01T00:00:00.000',
      'end_date': null,
      'status': 'ACTIVE',
      'created_at': '2026-08-01T00:00:00.000',
      'updated_at': '2026-08-01T00:00:00.000',
    };
  }

  /// Asserts that [contents] is rejected, and that the message mentions [hint].
  void expectRejected(String contents, String hint) {
    expect(
      () => service.parse(contents),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.message.toLowerCase(),
          'message',
          contains(hint.toLowerCase()),
        ),
      ),
    );
  }

  group('the file itself', () {
    test('accepts a minimal valid document', () {
      final parsed = service.parse(document());
      expect(parsed.counts.total, 0);
    });

    test('rejects text that is not JSON', () {
      expectRejected('not a backup at all', 'valid json');
    });

    test('rejects empty contents', () {
      expectRejected('', 'valid json');
    });

    test('rejects a JSON array at the top level', () {
      expectRejected('[]', 'does not look like a finos backup');
    });

    test('rejects a JSON string at the top level', () {
      expectRejected('"hello"', 'does not look like a finos backup');
    });
  });

  group('version header', () {
    test('rejects a document with no version', () {
      expectRejected(document(includeVersion: false), 'no backup version');
    });

    test('rejects a non-numeric version', () {
      expectRejected(document(version: 'one'), 'unreadable version');
    });

    test('rejects a future format version', () {
      // Guessing at a format this build does not understand risks a
      // half-correct restore, which is worse than refusing.
      expectRejected(document(version: 99), 'format version 99');
    });
  });

  group('table structure', () {
    test('rejects a table that is not a list', () {
      expectRejected(
        document(transactions: {'not': 'a list'}),
        'is not a list',
      );
    });

    test('rejects an entry that is not a record', () {
      expectRejected(
        document(transactions: ['just a string']),
        'is not a record',
      );
    });

    test('treats a missing table as empty', () {
      // A backup written before a feature existed simply has nothing for it.
      final contents = jsonEncode({
        BackupFormat.versionKey: BackupFormat.version,
        BackupFormat.accountsKey: [account()],
      });

      final parsed = service.parse(contents);
      expect(parsed.accounts, hasLength(1));
      expect(parsed.budgets, isEmpty);
      expect(parsed.transactions, isEmpty);
    });

    test('names the offending entry position', () {
      final contents = document(
        accounts: [
          account(id: 'acct-1'),
          account(id: 'acct-2', name: 42),
        ],
      );

      // The index makes a bad record findable in a file with thousands of rows.
      expectRejected(contents, 'entry 2 in "accounts"');
    });
  });

  group('field validation', () {
    test('rejects a missing required field', () {
      final broken = account()..remove('name');
      expectRejected(document(accounts: [broken]), 'invalid name');
    });

    test('rejects a field of the wrong type', () {
      expectRejected(document(accounts: [account(name: 42)]), 'invalid name');
    });

    test('rejects an empty id', () {
      expectRejected(document(accounts: [account(id: '')]), 'empty id');
    });

    test('rejects an unrecognised enum value', () {
      expectRejected(
        document(accounts: [account(type: 'CRYPTO_WALLET')]),
        'unrecognised type',
      );
    });

    test('rejects a currency that is not three letters', () {
      expectRejected(
        document(accounts: [account(currency: 'TAKA')]),
        'three-letter code',
      );
    });

    test('rejects an unreadable date', () {
      final broken = account()..['created_at'] = 'last Tuesday';
      expectRejected(document(accounts: [broken]), 'unreadable created_at');
    });

    test('allows an empty description', () {
      final parsed = service.parse(
        document(accounts: [account()], transactions: [transaction()]),
      );
      expect(parsed.transactions.single.description, isEmpty);
    });
  });

  group('money', () {
    test('rejects a decimal amount', () {
      // Money is integer minor units (docs/DATA_MODEL.md §4); a decimal here
      // means precision was already lost upstream.
      expectRejected(
        document(
          accounts: [account()],
          transactions: [transaction(amountMinor: 1500.5)],
        ),
        'whole number',
      );
    });

    test('rejects a string amount', () {
      expectRejected(
        document(
          accounts: [account()],
          transactions: [transaction(amountMinor: '1500')],
        ),
        'whole number',
      );
    });

    test('rejects a zero transaction amount', () {
      expectRejected(
        document(
          accounts: [account()],
          transactions: [transaction(amountMinor: 0)],
        ),
        'greater than zero',
      );
    });

    test('rejects a negative transaction amount', () {
      expectRejected(
        document(
          accounts: [account()],
          transactions: [transaction(amountMinor: -500)],
        ),
        'greater than zero',
      );
    });

    test('rejects a zero budget limit', () {
      expectRejected(
        document(categories: [category()], budgets: [budget(amountMinor: 0)]),
        'greater than zero',
      );
    });

    test('accepts a zero opening balance', () {
      // Unlike amounts, an opening balance of zero is perfectly normal.
      final parsed = service.parse(
        document(accounts: [account(openingBalanceMinor: 0)]),
      );
      expect(parsed.accounts.single.openingBalanceMinor, 0);
    });

    test('accepts a negative opening balance', () {
      // A credit card can legitimately start overdrawn.
      final parsed = service.parse(
        document(accounts: [account(openingBalanceMinor: -250000)]),
      );
      expect(parsed.accounts.single.openingBalanceMinor, -250000);
    });
  });

  group('duplicate ids', () {
    test('rejects two accounts sharing an id', () {
      expectRejected(
        document(accounts: [account(), account()]),
        'same account twice',
      );
    });

    test('rejects two transactions sharing an id', () {
      expectRejected(
        document(
          accounts: [account()],
          transactions: [transaction(), transaction()],
        ),
        'same transaction twice',
      );
    });
  });

  group('references within the backup', () {
    test('rejects a transaction pointing at a missing account', () {
      expectRejected(
        document(transactions: [transaction(accountId: 'acct-ghost')]),
        'account that the backup does not contain',
      );
    });

    test('rejects a transfer pointing at a missing destination', () {
      expectRejected(
        document(
          accounts: [account()],
          transactions: [
            transaction(type: 'TRANSFER', destinationAccountId: 'acct-ghost'),
          ],
        ),
        'destination account that the backup does not contain',
      );
    });

    test('rejects a transaction pointing at a missing category', () {
      expectRejected(
        document(
          accounts: [account()],
          transactions: [transaction(categoryId: 'cat-ghost')],
        ),
        'category that the backup does not contain',
      );
    });

    test('rejects a budget pointing at a missing category', () {
      expectRejected(
        document(budgets: [budget(categoryId: 'cat-ghost')]),
        'category that the backup does not contain',
      );
    });

    test('accepts references that all resolve', () {
      final parsed = service.parse(
        document(
          accounts: [
            account(id: 'acct-1'),
            account(id: 'acct-2'),
          ],
          categories: [category(id: 'cat-1')],
          transactions: [
            transaction(id: 'tx-1', categoryId: 'cat-1'),
            transaction(
              id: 'tx-2',
              type: 'TRANSFER',
              destinationAccountId: 'acct-2',
            ),
          ],
          budgets: [budget(categoryId: 'cat-1')],
        ),
      );

      expect(parsed.counts.accounts, 2);
      expect(parsed.counts.categories, 1);
      expect(parsed.counts.transactions, 2);
      expect(parsed.counts.budgets, 1);
    });
  });

  group('nothing is written while validating', () {
    test('a rejected file leaves the database untouched', () async {
      final before = await service.currentCounts();

      expect(
        () => service.parse('{"backup_version": 1, "accounts": "broken"}'),
        throwsA(isA<ValidationException>()),
      );

      expect(await service.currentCounts(), before);
    });
  });
}
