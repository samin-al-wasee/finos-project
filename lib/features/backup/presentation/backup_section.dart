import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../application/csv_export_service.dart';
import '../domain/backup_envelope.dart';

/// The Data rows in Settings: export a backup, restore one, or export
/// transactions as CSV (FR-08).
///
/// Restoring replaces every financial record, so it always goes through a
/// confirmation that states — in records — both what will be written and what
/// will be lost. The CSV export is read-only and needs no such confirmation.
///
/// Both export rows carry a visible warning that the file holds sensitive
/// financial information (NFR-04) — stated up front rather than after the
/// share sheet opens, since by then the file may already be on its way
/// somewhere else.
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          enabled: !_busy,
          leading: const Icon(Icons.upload_outlined),
          title: const Text('Export backup'),
          subtitle: const Text(
            'Save a copy of all your financial data. It contains sensitive '
            'information — store and share it carefully.',
          ),
          isThreeLine: true,
          trailing: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _busy ? null : _export,
        ),
        ListTile(
          enabled: !_busy,
          leading: const Icon(Icons.download_outlined),
          title: const Text('Import backup'),
          subtitle: const Text('Replace your data with a saved backup'),
          onTap: _busy ? null : _import,
        ),
        ListTile(
          enabled: !_busy,
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('Export transactions (CSV)'),
          subtitle: const Text(
            'Save your transactions for a spreadsheet. It contains sensitive '
            'financial information — store and share it carefully.',
          ),
          isThreeLine: true,
          onTap: _busy ? null : _exportCsv,
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Export
  // ------------------------------------------------------------------

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      final contents = await service.export();
      final shared = await ref
          .read(backupFileStoreProvider)
          .exportBackup(contents, BackupFormat.fileNameFor(DateTime.now()));

      if (!mounted) return;
      // A dismissed share sheet is a deliberate cancellation, not a failure.
      if (shared) _tell('Backup exported');
    } catch (error) {
      if (mounted) _tell(userMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final service = ref.read(csvExportServiceProvider);
      final contents = await service.exportTransactions();
      final shared = await ref
          .read(backupFileStoreProvider)
          .exportCsv(contents, CsvExportService.fileNameFor(DateTime.now()));

      if (!mounted) return;
      // A dismissed share sheet is a deliberate cancellation, not a failure.
      if (shared) _tell('Transactions exported');
    } catch (error) {
      if (mounted) _tell(userMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------
  // Import
  // ------------------------------------------------------------------

  Future<void> _import() async {
    try {
      // No spinner while the OS file picker is up: the app is waiting on the
      // user, not working.
      final contents = await ref.read(backupFileStoreProvider).pickBackup();
      if (contents == null) return; // Cancelled at the file picker.
      if (!mounted) return;

      final service = ref.read(backupServiceProvider);
      setState(() => _busy = true);
      // Parse and validate before anything is touched, so an unreadable file is
      // rejected without the user ever seeing a confirmation prompt.
      final backup = service.parse(contents);
      final existing = await service.currentCounts();
      if (!mounted) return;
      // Released before the dialog: a progress indicator must not keep spinning
      // while a modal waits for an answer.
      setState(() => _busy = false);

      final confirmed = await _confirmRestore(
        incoming: backup.counts,
        existing: existing,
      );
      if (confirmed != true || !mounted) return;

      setState(() => _busy = true);
      final restored = await service.restore(backup);
      if (mounted) {
        _tell('Restored ${_describe(restored)}');
      }
    } catch (error) {
      if (mounted) _tell(userMessageFor(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmRestore({
    required BackupCounts incoming,
    required BackupCounts existing,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace all data?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This backup contains ${_describe(incoming)}.'),
            const SizedBox(height: 12),
            Text(
              existing.isEmpty
                  ? 'There is nothing on this device to replace.'
                  : 'It will replace ${_describe(existing)} currently on this '
                        'device.',
            ),
            const SizedBox(height: 12),
            const Text('This cannot be undone.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  /// Renders counts as "5 accounts, 12 categories, 247 transactions".
  ///
  /// Empty sections are omitted so the sentence stays readable.
  static String _describe(BackupCounts counts) {
    final parts = <String>[
      if (counts.accounts > 0) _plural(counts.accounts, 'account'),
      if (counts.categories > 0)
        _plural(counts.categories, 'category', plural: 'categories'),
      if (counts.transactions > 0) _plural(counts.transactions, 'transaction'),
      if (counts.budgets > 0) _plural(counts.budgets, 'budget'),
    ];
    if (parts.isEmpty) return 'no records';
    if (parts.length == 1) return parts.single;
    return '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
  }

  static String _plural(int count, String singular, {String? plural}) =>
      count == 1 ? '$count $singular' : '$count ${plural ?? '${singular}s'}';

  void _tell(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
