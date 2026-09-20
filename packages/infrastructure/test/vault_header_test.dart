import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  const codec = VaultHeaderCodec();
  final header = VaultHeader(
    vaultUuid: '00112233-4455-6677-8899-aabbccddeeff',
    salt: Uint8List(16),
    wrapNonce: Uint8List(24),
    wrappedMasterKey: Uint8List(48),
  );

  test('matches the canonical v1 byte vector and round trips', () {
    final encoded = codec.encode(header);
    const json =
        '{"format":1,"kdf":{"algorithm":"argon2id13",'
        '"iterations":3,"memory_kib":65536,"parallelism":1,'
        '"salt":"AAAAAAAAAAAAAAAAAAAAAA"},'
        '"vault_uuid":"00112233-4455-6677-8899-aabbccddeeff",'
        '"wrap":{"algorithm":"xchacha20poly1305-ietf",'
        '"ciphertext":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",'
        '"nonce":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}}';
    final jsonBytes = utf8.encode(json);

    expect(encoded.sublist(0, 7), [0x53, 0x54, 0x56, 0x4c, 0x54, 0, 1]);
    expect(ByteData.sublistView(encoded).getUint32(7), jsonBytes.length);
    expect(encoded.sublist(11), jsonBytes);
    expect(codec.encode(codec.decode(encoded)), encoded);
    expect(
      uuidBytes(header.vaultUuid),
      List<int>.generate(16, (i) => i * 0x11),
    );
  });

  test('rejects trailing, truncated, non-canonical and unknown fields', () {
    final valid = codec.encode(header);
    expect(
      () => codec.decode(Uint8List.fromList([...valid, 0])),
      throwsA(isA<CorruptVaultDataFailure>()),
    );
    expect(
      () => codec.decode(Uint8List.sublistView(valid, 0, valid.length - 1)),
      throwsA(isA<CorruptVaultDataFailure>()),
    );

    final payload = utf8.decode(valid.sublist(11));
    final unknown = payload.replaceFirst('{', '{"extra":true,');
    final unknownBytes = _withPayload(unknown);
    expect(
      () => codec.decode(unknownBytes),
      throwsA(isA<UnsupportedVaultFormatFailure>()),
    );

    final spaced = _withPayload(payload.replaceFirst('{', '{ '));
    expect(() => codec.decode(spaced), throwsA(isA<CorruptVaultDataFailure>()));
  });

  test('rejects duplicate keys because they are not canonical', () {
    final valid = codec.encode(header);
    final payload = utf8.decode(valid.sublist(11));
    final duplicate = payload.replaceFirst('{', '{"format":1,');
    expect(
      () => codec.decode(_withPayload(duplicate)),
      throwsA(isA<CorruptVaultDataFailure>()),
    );
  });
}

Uint8List _withPayload(String payload) {
  final payloadBytes = utf8.encode(payload);
  final bytes = Uint8List(11 + payloadBytes.length)
    ..setRange(0, 7, [0x53, 0x54, 0x56, 0x4c, 0x54, 0, 1]);
  ByteData.sublistView(bytes).setUint32(7, payloadBytes.length);
  bytes.setRange(11, bytes.length, payloadBytes);
  return bytes;
}
