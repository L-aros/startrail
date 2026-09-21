import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  const codec = BackupHeaderCodec();
  final header = BackupHeader(
    vaultUuid: '00112233-4455-6677-8899-aabbccddeeff',
    salt: Uint8List(16),
    wrapNonce: Uint8List(24),
    wrappedBackupKey: Uint8List(48),
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

    expect(encoded.sublist(0, 7), [0x53, 0x54, 0x42, 0x4b, 0x50, 0, 1]);
    expect(ByteData.sublistView(encoded).getUint32(7), jsonBytes.length);
    expect(encoded.sublist(11), jsonBytes);
    expect(codec.encode(codec.decode(encoded)), encoded);
  });

  test('rejects wrong magic and truncated input', () {
    final valid = codec.encode(header);
    final wrongMagic = Uint8List.fromList(valid)..[0] = 0x00;
    expect(
      () => codec.decode(wrongMagic),
      throwsA(isA<UnsupportedVaultFormatFailure>()),
    );
    expect(
      () => codec.decode(Uint8List.sublistView(valid, 0, valid.length - 1)),
      throwsA(isA<CorruptVaultDataFailure>()),
    );
  });

  test('rejects unknown fields and non-canonical payload', () {
    final valid = codec.encode(header);
    final payload = utf8.decode(valid.sublist(11));
    final unknown = payload.replaceFirst('{', '{"extra":true,');
    expect(
      () => codec.decode(_withPayload(unknown)),
      throwsA(isA<UnsupportedVaultFormatFailure>()),
    );
    final spaced = payload.replaceFirst('{', '{ ');
    expect(
      () => codec.decode(_withPayload(spaced)),
      throwsA(isA<CorruptVaultDataFailure>()),
    );
  });

  test('rejects a downgraded KDF parameter set', () {
    final valid = codec.encode(header);
    final payload = utf8.decode(valid.sublist(11));
    for (final downgrade in [
      '"memory_kib":65535',
      '"memory_kib":16384',
      '"iterations":2',
      '"iterations":1',
      '"algorithm":"argon2id"',
    ]) {
      final original = downgrade.startsWith('"memory_kib"')
          ? '"memory_kib":65536'
          : downgrade.startsWith('"iterations"')
          ? '"iterations":3'
          : '"algorithm":"argon2id13"';
      final tampered = payload.replaceFirst(original, downgrade);
      expect(
        () => codec.decode(_withPayload(tampered)),
        throwsA(isA<UnsupportedVaultFormatFailure>()),
        reason: 'downgrade $downgrade must be rejected',
      );
    }
  });
}

Uint8List _withPayload(String payload) {
  final payloadBytes = utf8.encode(payload);
  final bytes = Uint8List(11 + payloadBytes.length)
    ..setRange(0, 7, [0x53, 0x54, 0x42, 0x4b, 0x50, 0, 1]);
  ByteData.sublistView(bytes).setUint32(7, payloadBytes.length);
  bytes.setRange(11, bytes.length, payloadBytes);
  return bytes;
}
