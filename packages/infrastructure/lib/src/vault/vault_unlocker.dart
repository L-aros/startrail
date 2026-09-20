import 'dart:io';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../crypto/password_kdf.dart';
import '../crypto/vault_key_wrapper.dart';
import '../crypto/vault_object_crypto.dart';
import '../format/head.dart';
import '../format/manifest_v1.dart';
import '../format/object_envelope.dart';
import '../format/vault_header.dart';

final class UnlockedVault {
  UnlockedVault({
    required this.vaultUuid,
    required this.masterKey,
    required this.manifestPlaintext,
  });

  final String vaultUuid;
  final SecureKey masterKey;
  final Uint8List manifestPlaintext;
  var _disposed = false;

  void dispose() {
    if (_disposed) return;
    manifestPlaintext.fillRange(0, manifestPlaintext.length, 0);
    masterKey.dispose();
    _disposed = true;
  }
}

final class VaultUnlocker {
  VaultUnlocker._(this._sodium);

  static Future<VaultUnlocker> initialize() async =>
      VaultUnlocker._(await SodiumSumoInit.init());

  final SodiumSumo _sodium;

  Future<UnlockedVault> unlock({
    required Directory vault,
    required Int8List passwordBytes,
  }) async {
    final separator = Platform.pathSeparator;
    final headerBytes = await File(
      '${vault.path}${separator}vault.header',
    ).readAsBytes();
    final header = const VaultHeaderCodec().decode(headerBytes);
    final kek = PasswordKdf(
      _sodium,
    ).deriveKey(passwordBytes: passwordBytes, salt: header.salt);
    SecureKey? masterKey;
    try {
      masterKey = VaultKeyWrapper(_sodium).unwrap(
        ciphertext: header.wrappedMasterKey,
        nonce: header.wrapNonce,
        keyEncryptionKey: kek,
        vaultUuid: header.vaultUuid,
      );
      final headBytes = await File(
        '${vault.path}${separator}HEAD',
      ).readAsBytes();
      final head = const VaultHeadCodec().decode(headBytes);
      final manifestBytes = await File(
        '${vault.path}${separator}manifests$separator'
        '${head.manifest.manifestId}',
      ).readAsBytes();
      const VaultHeadCodec().verifyManifest(head, manifestBytes);
      final envelope = const ObjectEnvelopeCodec().decode(manifestBytes);
      if (envelope.type != VaultObjectType.manifest ||
          envelope.schemaVersion != 1) {
        throw const UnsupportedVaultFormatFailure();
      }
      final plaintext = VaultObjectCrypto(_sodium).decrypt(
        envelopeBytes: manifestBytes,
        masterKey: masterKey,
        vaultUuid: uuidBytes(header.vaultUuid),
      );
      validateManifestV1(plaintext);
      final session = UnlockedVault(
        vaultUuid: header.vaultUuid,
        masterKey: masterKey,
        manifestPlaintext: plaintext,
      );
      masterKey = null;
      return session;
    } finally {
      masterKey?.dispose();
      kek.dispose();
    }
  }
}
