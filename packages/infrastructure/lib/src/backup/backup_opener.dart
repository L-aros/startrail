import 'dart:io';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../crypto/password_kdf.dart';
import '../format/backup_header.dart';
import '../format/backup_manifest.dart';
import 'backup_container.dart';
import 'backup_crypto.dart';

/// A backup container that has been authenticated and whose manifest has been
/// decrypted. File bytes begin at [filesStartOffset] and are plaintext copies
/// of the Vault's already-encrypted authoritative files, so no further key is
/// needed to read them.
final class OpenedBackup {
  OpenedBackup({
    required this.header,
    required this.manifest,
    required this.manifestCiphertext,
    required this.filesStartOffset,
  });

  final BackupHeader header;
  final BackupManifest manifest;
  final Uint8List manifestCiphertext;
  final int filesStartOffset;
}

/// Shared reader that authenticates a backup container and returns its
/// decrypted manifest plus the offset where file bytes begin. Used by both the
/// verifier and the restorer so their error mapping stays identical.
///
/// Throws [VaultAuthenticationFailure] on a wrong password,
/// [SodiumException] when the manifest is tampered, and the usual
/// [VaultFailure] types for structural or format problems.
final class BackupOpener {
  BackupOpener(this._sodium);

  final SodiumSumo _sodium;
  final BackupHeaderCodec _headerCodec = const BackupHeaderCodec();
  final BackupManifestCodec _manifestCodec = const BackupManifestCodec();

  Future<OpenedBackup> open({
    required RandomAccessFile handle,
    required Int8List passwordBytes,
  }) async {
    final magic = await handle.read(backupMagic.length);
    if (magic.length != backupMagic.length) {
      throw const CorruptVaultDataFailure();
    }
    if (!_bytesEqual(magic, Uint8List.fromList(backupMagic))) {
      throw const UnsupportedVaultFormatFailure();
    }

    final headerLengthBytes = await handle.read(4);
    if (headerLengthBytes.length != 4) {
      throw const CorruptVaultDataFailure();
    }
    final headerLength = ByteData.sublistView(headerLengthBytes).getUint32(0);
    if (headerLength > backupMaxHeaderLength) {
      throw const CorruptVaultDataFailure();
    }
    final headerBytes = await handle.read(headerLength);
    if (headerBytes.length != headerLength) {
      throw const CorruptVaultDataFailure();
    }
    final header = _headerCodec.decode(headerBytes);

    final kek = PasswordKdf(
      _sodium,
    ).deriveKey(passwordBytes: passwordBytes, salt: header.salt);
    final backupKey = BackupCrypto(_sodium).unwrapBackupKey(
      ciphertext: header.wrappedBackupKey,
      nonce: header.wrapNonce,
      keyEncryptionKey: kek,
      vaultUuid: header.vaultUuid,
    );
    try {
      final nonce = await handle.read(backupManifestNonceBytes);
      if (nonce.length != backupManifestNonceBytes) {
        throw const CorruptVaultDataFailure();
      }
      final lengthBytes = await handle.read(8);
      if (lengthBytes.length != 8) {
        throw const CorruptVaultDataFailure();
      }
      final manifestLength = decodeUint64Be(lengthBytes);
      if (manifestLength > backupMaxManifestLength) {
        throw const CorruptVaultDataFailure();
      }
      final manifestCiphertext = await handle.read(manifestLength);
      if (manifestCiphertext.length != manifestLength) {
        throw const CorruptVaultDataFailure();
      }
      final plaintext = BackupCrypto(_sodium).openManifest(
        nonce: nonce,
        ciphertext: manifestCiphertext,
        backupKey: backupKey,
        vaultUuid: header.vaultUuid,
      );
      try {
        final manifest = _manifestCodec.decode(plaintext);
        if (manifest.vaultUuid != header.vaultUuid) {
          throw const CorruptVaultDataFailure();
        }
        return OpenedBackup(
          header: header,
          manifest: manifest,
          manifestCiphertext: manifestCiphertext,
          filesStartOffset: await handle.position(),
        );
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }
    } finally {
      backupKey.dispose();
      kek.dispose();
    }
  }
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
