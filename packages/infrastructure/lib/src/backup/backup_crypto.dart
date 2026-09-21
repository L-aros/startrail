import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../format/vault_header.dart';

const _backupKeyAdPrefix = 'startrail/backup-key/v1';
const _backupManifestAdPrefix = 'startrail/backup-manifest/v1';

/// A Backup Key wrapped under the password-derived KEK.
final class WrappedBackupKey {
  WrappedBackupKey({required Uint8List nonce, required Uint8List ciphertext})
    : nonce = Uint8List.fromList(nonce),
      ciphertext = Uint8List.fromList(ciphertext);

  final Uint8List nonce;
  final Uint8List ciphertext;
}

/// A backup manifest sealed under the Backup Key.
final class SealedBackupManifest {
  SealedBackupManifest({
    required Uint8List nonce,
    required Uint8List ciphertext,
  }) : nonce = Uint8List.fromList(nonce),
       ciphertext = Uint8List.fromList(ciphertext);

  final Uint8List nonce;
  final Uint8List ciphertext;
}

/// Backup-specific key wrapping and manifest AEAD. Reuses the audited
/// XChaCha20-Poly1305 primitive with domain-separated additional data so a
/// backup key or manifest cannot be confused with a Vault key or object.
final class BackupCrypto {
  BackupCrypto(this._sodium);

  final SodiumSumo _sodium;

  SecureKey generateBackupKey() =>
      _sodium.crypto.aeadXChaCha20Poly1305IETF.keygen();

  WrappedBackupKey wrapBackupKey({
    required SecureKey backupKey,
    required SecureKey keyEncryptionKey,
    required String vaultUuid,
  }) {
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = _sodium.randombytes.buf(aead.nonceBytes);
    final ciphertext = backupKey.runUnlockedSync(
      (bytes) => aead.encrypt(
        message: bytes,
        nonce: nonce,
        key: keyEncryptionKey,
        additionalData: backupKeyAdditionalData(vaultUuid),
      ),
    );
    return WrappedBackupKey(nonce: nonce, ciphertext: ciphertext);
  }

  SecureKey unwrapBackupKey({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required SecureKey keyEncryptionKey,
    required String vaultUuid,
  }) {
    Uint8List? plaintext;
    try {
      plaintext = _sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: ciphertext,
        nonce: nonce,
        key: keyEncryptionKey,
        additionalData: backupKeyAdditionalData(vaultUuid),
      );
      if (plaintext.length != 32) throw const VaultAuthenticationFailure();
      return _sodium.secureCopy(plaintext);
    } on SodiumException {
      throw const VaultAuthenticationFailure();
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  SealedBackupManifest sealManifest({
    required Uint8List plaintext,
    required SecureKey backupKey,
    required String vaultUuid,
  }) {
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = _sodium.randombytes.buf(aead.nonceBytes);
    final ciphertext = aead.encrypt(
      message: plaintext,
      nonce: nonce,
      key: backupKey,
      additionalData: backupManifestAdditionalData(vaultUuid),
    );
    return SealedBackupManifest(nonce: nonce, ciphertext: ciphertext);
  }

  /// Decrypts a sealed manifest; throws [SodiumException] on authentication
  /// failure so callers can distinguish a tampered manifest from a wrong
  /// password (which fails earlier, at [unwrapBackupKey]).
  Uint8List openManifest({
    required Uint8List nonce,
    required Uint8List ciphertext,
    required SecureKey backupKey,
    required String vaultUuid,
  }) {
    return _sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
      cipherText: ciphertext,
      nonce: nonce,
      key: backupKey,
      additionalData: backupManifestAdditionalData(vaultUuid),
    );
  }
}

Uint8List backupKeyAdditionalData(String vaultUuid) =>
    _additionalData(_backupKeyAdPrefix, vaultUuid);

Uint8List backupManifestAdditionalData(String vaultUuid) =>
    _additionalData(_backupManifestAdPrefix, vaultUuid);

Uint8List _additionalData(String prefix, String vaultUuid) {
  final prefixBytes = utf8.encode(prefix);
  final uuid = uuidBytes(vaultUuid);
  return Uint8List(prefixBytes.length + uuid.length)
    ..setRange(0, prefixBytes.length, prefixBytes)
    ..setRange(prefixBytes.length, prefixBytes.length + uuid.length, uuid);
}
