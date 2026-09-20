import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../format/vault_header.dart';

const _headerAdPrefix = 'startrail/vault-header/v1';

final class WrappedMasterKey {
  WrappedMasterKey({required Uint8List nonce, required Uint8List ciphertext})
    : nonce = Uint8List.fromList(nonce),
      ciphertext = Uint8List.fromList(ciphertext);

  final Uint8List nonce;
  final Uint8List ciphertext;
}

final class VaultKeyWrapper {
  VaultKeyWrapper(this._sodium);

  final SodiumSumo _sodium;

  WrappedMasterKey wrap({
    required SecureKey masterKey,
    required SecureKey keyEncryptionKey,
    required String vaultUuid,
  }) {
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = _sodium.randombytes.buf(aead.nonceBytes);
    final ciphertext = masterKey.runUnlockedSync(
      (bytes) => aead.encrypt(
        message: bytes,
        nonce: nonce,
        key: keyEncryptionKey,
        additionalData: headerAdditionalData(vaultUuid),
      ),
    );
    return WrappedMasterKey(nonce: nonce, ciphertext: ciphertext);
  }

  SecureKey unwrap({
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
        additionalData: headerAdditionalData(vaultUuid),
      );
      if (plaintext.length != 32) throw const VaultAuthenticationFailure();
      return _sodium.secureCopy(plaintext);
    } on SodiumException {
      throw const VaultAuthenticationFailure();
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }
}

Uint8List headerAdditionalData(String vaultUuid) {
  final prefix = utf8.encode(_headerAdPrefix);
  final uuid = uuidBytes(vaultUuid);
  return Uint8List(prefix.length + uuid.length)
    ..setRange(0, prefix.length, prefix)
    ..setRange(prefix.length, prefix.length + uuid.length, uuid);
}
