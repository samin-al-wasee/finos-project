import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/app_exception.dart';

/// Moves backup files between FinOS and the rest of the device.
///
/// This is the only part of the backup feature that touches plugins, and it is
/// an interface so tests can substitute a fake: method channels are unavailable
/// under `flutter test`, and serialisation, validation, and restore must stay
/// fully testable without them.
abstract interface class BackupFileStore {
  /// Hands [contents] to the OS so the user can keep it.
  ///
  /// Returns `false` if the user dismissed the share sheet without choosing a
  /// destination.
  Future<bool> exportBackup(String contents, String fileName);

  /// Hands CSV [contents] to the OS so the user can keep it (FR-08).
  ///
  /// Returns `false` if the user dismissed the share sheet without choosing a
  /// destination.
  Future<bool> exportCsv(String contents, String fileName);

  /// Asks the user to pick a backup file and returns its contents.
  ///
  /// Returns `null` if the user cancelled.
  Future<String?> pickBackup();
}

/// The real implementation, backed by the platform share sheet and file picker.
///
/// Export writes to the temporary directory and then shares that file: on both
/// Android and iOS the share sheet is the route to "save to Files"/Drive/email,
/// and it needs a real path. The temporary copy is deleted afterwards — a
/// readable copy of the user's whole financial history should not linger in a
/// cache directory (docs/DATA_MODEL.md §54).
class PlatformBackupFileStore implements BackupFileStore {
  const PlatformBackupFileStore();

  @override
  Future<bool> exportBackup(String contents, String fileName) => _share(
    contents,
    fileName,
    mimeType: 'application/json',
    subject: 'FinOS backup',
    failureMessage: 'The backup could not be shared. Please try again.',
  );

  @override
  Future<bool> exportCsv(String contents, String fileName) => _share(
    contents,
    fileName,
    mimeType: 'text/csv',
    subject: 'FinOS transactions',
    failureMessage: 'The transactions could not be shared. Please try again.',
  );

  Future<bool> _share(
    String contents,
    String fileName, {
    required String mimeType,
    required String subject,
    required String failureMessage,
  }) async {
    File? file;
    try {
      final directory = await getTemporaryDirectory();
      file = File('${directory.path}/$fileName');
      await file.writeAsString(contents, flush: true);

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mimeType)],
          fileNameOverrides: [fileName],
          subject: subject,
        ),
      );
      return result.status != ShareResultStatus.dismissed;
    } on AppException {
      rethrow;
    } catch (_) {
      // Nothing is logged: the failure context would include the backup path
      // and contents (AGENTS.md §15).
      throw UnexpectedException(failureMessage);
    } finally {
      // Best-effort cleanup; a failure to delete must not mask the outcome.
      try {
        if (file != null && file.existsSync()) await file.delete();
      } catch (_) {
        // Ignored deliberately.
      }
    }
  }

  @override
  Future<String?> pickBackup() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'FinOS backup',
            extensions: ['json'],
            // iOS and macOS match on UTIs rather than extensions.
            uniformTypeIdentifiers: ['public.json'],
            mimeTypes: ['application/json'],
          ),
        ],
      );
      if (file == null) return null;
      return await file.readAsString();
    } catch (_) {
      throw const UnexpectedException(
        'That file could not be opened. Please try again.',
      );
    }
  }
}
