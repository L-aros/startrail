import 'dart:typed_data';

import 'package:domain/domain.dart';

const _magic = <int>[0x53, 0x54, 0x4f, 0x42]; // STOB
const _version = 1;
const _nonceLength = 24;
const _tagLength = 16;
const _headerLength = 4 + 1 + 1 + 2 + _nonceLength;

final class ObjectEnvelope {
  ObjectEnvelope({
    required this.type,
    required this.schemaVersion,
    required Uint8List nonce,
    required Uint8List ciphertext,
  }) : nonce = Uint8List.fromList(nonce),
       ciphertext = Uint8List.fromList(ciphertext);

  final VaultObjectType type;
  final int schemaVersion;
  final Uint8List nonce;
  final Uint8List ciphertext;
}

final class ObjectEnvelopeCodec {
  const ObjectEnvelopeCodec();

  Uint8List encode(ObjectEnvelope envelope) {
    if (envelope.nonce.length != _nonceLength) {
      throw ArgumentError.value(envelope.nonce.length, 'nonce.length');
    }
    if (envelope.schemaVersion < 0 || envelope.schemaVersion > 0xffff) {
      throw ArgumentError.value(envelope.schemaVersion, 'schemaVersion');
    }
    if (envelope.ciphertext.length < _tagLength) {
      throw ArgumentError.value(
        envelope.ciphertext.length,
        'ciphertext.length',
      );
    }
    final output = Uint8List(_headerLength + envelope.ciphertext.length);
    output.setRange(0, 4, _magic);
    output[4] = _version;
    output[5] = envelope.type.wireValue;
    ByteData.sublistView(output).setUint16(6, envelope.schemaVersion);
    output.setRange(8, _headerLength, envelope.nonce);
    output.setRange(_headerLength, output.length, envelope.ciphertext);
    return output;
  }

  ObjectEnvelope decode(Uint8List bytes) {
    if (bytes.length < _headerLength + _tagLength) {
      throw const CorruptVaultDataFailure();
    }
    for (var index = 0; index < _magic.length; index++) {
      if (bytes[index] != _magic[index]) {
        throw const CorruptVaultDataFailure();
      }
    }
    if (bytes[4] != _version) {
      throw const UnsupportedVaultFormatFailure();
    }
    final type = VaultObjectType.fromWireValue(bytes[5]);
    if (type == null) throw const UnsupportedVaultFormatFailure();
    return ObjectEnvelope(
      type: type,
      schemaVersion: ByteData.sublistView(bytes).getUint16(6),
      nonce: Uint8List.sublistView(bytes, 8, _headerLength),
      ciphertext: Uint8List.sublistView(bytes, _headerLength),
    );
  }
}
