import 'dart:typed_data';

import 'backup.dart';

/// The restore target already contains a non-empty Vault and no replacement
/// was confirmed.
final class BackupTargetOccupied implements Exception {
  const BackupTargetOccupied();
}

/// Port implemented by the infrastructure Vault adapter. The domain and
/// application layers depend on this interface only, never on storage or
/// crypto internals.
abstract interface class BackupStore {
  /// Creates an encrypted backup of the currently-open Vault and writes it to
  /// [targetPath], returning a non-sensitive summary. The password is
  /// re-supplied so the backup key is wrapped under a fresh password-derived
  /// KEK independent of the live session.
  Future<BackupSummary> createBackup({
    required String targetPath,
    required Int8List passwordBytes,
  });

  /// Verifies [backupPath] in isolation. Never reads or writes any Vault.
  Future<BackupVerificationReport> verifyBackup({
    required String backupPath,
    required Int8List passwordBytes,
  });

  /// Restores [backupPath] into [targetPath]. Refuses to overwrite a non-empty
  /// target unless [replaceExisting] is true; on any failure the target is
  /// left untouched.
  Future<void> restoreBackup({
    required String backupPath,
    required Int8List passwordBytes,
    required String targetPath,
    required bool replaceExisting,
  });
}
