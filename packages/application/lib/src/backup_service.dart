import 'dart:io';
import 'dart:typed_data';

import 'package:domain/domain.dart';

/// Stable, non-sensitive application error codes for backup/recovery.
sealed class BackupError implements Exception {
  const BackupError(this.code);

  final String code;

  @override
  String toString() => code;
}

final class BackupWrongPasswordError extends BackupError {
  const BackupWrongPasswordError() : super('BACKUP_WRONG_PASSWORD');
}

final class BackupCorruptError extends BackupError {
  const BackupCorruptError() : super('BACKUP_CORRUPT');
}

final class BackupUnsupportedError extends BackupError {
  const BackupUnsupportedError() : super('BACKUP_UNSUPPORTED');
}

final class BackupTargetOccupiedError extends BackupError {
  const BackupTargetOccupiedError() : super('BACKUP_TARGET_OCCUPIED');
}

final class BackupIoError extends BackupError {
  const BackupIoError() : super('BACKUP_IO');
}

/// Use cases for creating, verifying and restoring encrypted backups.
///
/// Maps domain and infrastructure failures to stable [BackupError] codes so
/// the UI never sees storage or crypto internals. [verifyBackup] returns a
/// [BackupVerificationReport] whose status already distinguishes wrong
/// password, tampering, corruption and unsupported formats.
final class BackupService {
  BackupService(this._store);

  final BackupStore _store;

  Future<BackupSummary> createBackup({
    required String targetPath,
    required Int8List passwordBytes,
  }) async {
    try {
      return await _store.createBackup(
        targetPath: targetPath,
        passwordBytes: passwordBytes,
      );
    } on FileSystemException {
      throw const BackupIoError();
    } on StateError {
      throw const BackupIoError();
    }
  }

  Future<BackupVerificationReport> verifyBackup({
    required String backupPath,
    required Int8List passwordBytes,
  }) {
    return _store.verifyBackup(
      backupPath: backupPath,
      passwordBytes: passwordBytes,
    );
  }

  Future<void> restoreBackup({
    required String backupPath,
    required Int8List passwordBytes,
    required String targetPath,
    required bool replaceExisting,
  }) async {
    try {
      await _store.restoreBackup(
        backupPath: backupPath,
        passwordBytes: passwordBytes,
        targetPath: targetPath,
        replaceExisting: replaceExisting,
      );
    } on BackupTargetOccupied {
      throw const BackupTargetOccupiedError();
    } on VaultAuthenticationFailure {
      throw const BackupWrongPasswordError();
    } on UnsupportedVaultFormatFailure {
      throw const BackupUnsupportedError();
    } on CorruptVaultDataFailure {
      throw const BackupCorruptError();
    } on FileSystemException {
      throw const BackupIoError();
    }
  }
}
