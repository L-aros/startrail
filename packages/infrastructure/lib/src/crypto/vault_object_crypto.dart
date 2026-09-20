import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../format/object_envelope.dart';

const _objectAdPrefix = 'startrail/object/v1';

final class VaultObjectCrypto {
  VaultObjectCrypto(this._sodium);

  static Future<VaultObjectCrypto> initialize() async =>
      VaultObjectCrypto(await SodiumSumoInit.init());

  final SodiumSumo _sodium;
  final ObjectEnvelopeCodec _codec = const ObjectEnvelopeCodec();

  SecureKey generateMasterKey() =>
      _sodium.crypto.aeadXChaCha20Poly1305IETF.keygen();

  Uint8List encrypt({
    required Uint8List plaintext,
    required SecureKey masterKey,
    required Uint8List vaultUuid,
    required VaultObjectType type,
    required int schemaVersion,
  }) {
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = _sodium.randombytes.buf(aead.nonceBytes);
    final ciphertext = aead.encrypt(
      message: plaintext,
      nonce: nonce,
      key: masterKey,
      additionalData: objectAdditionalData(
        vaultUuid: vaultUuid,
        type: type,
        schemaVersion: schemaVersion,
      ),
    );
    return _codec.encode(
      ObjectEnvelope(
        type: type,
        schemaVersion: schemaVersion,
        nonce: nonce,
        ciphertext: ciphertext,
      ),
    );
  }

  Uint8List decrypt({
    required Uint8List envelopeBytes,
    required SecureKey masterKey,
    required Uint8List vaultUuid,
  }) {
    final envelope = _codec.decode(envelopeBytes);
    try {
      return _sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: envelope.ciphertext,
        nonce: envelope.nonce,
        key: masterKey,
        additionalData: objectAdditionalData(
          vaultUuid: vaultUuid,
          type: envelope.type,
          schemaVersion: envelope.schemaVersion,
        ),
      );
    } on SodiumException {
      throw const VaultAuthenticationFailure();
    }
  }
}

Uint8List objectAdditionalData({
  required Uint8List vaultUuid,
  required VaultObjectType type,
  required int schemaVersion,
}) {
  if (vaultUuid.length != 16) {
    throw ArgumentError.value(vaultUuid.length, 'vaultUuid.length');
  }
  if (schemaVersion < 0 || schemaVersion > 0xffff) {
    throw ArgumentError.value(schemaVersion, 'schemaVersion');
  }
  final prefix = utf8.encode(_objectAdPrefix);
  final result = Uint8List(prefix.length + vaultUuid.length + 3);
  result.setRange(0, prefix.length, prefix);
  result.setRange(prefix.length, prefix.length + vaultUuid.length, vaultUuid);
  result[prefix.length + vaultUuid.length] = type.wireValue;
  ByteData.sublistView(result).setUint16(result.length - 2, schemaVersion);
  return result;
}
