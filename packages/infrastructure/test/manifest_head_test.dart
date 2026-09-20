import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  test('matches independent SHA-256 identity vectors', () {
    final identity = ManifestIdentity.fromCiphertext(
      Uint8List.fromList(utf8.encode('abc')),
    );

    expect(
      identity.manifestId,
      'xj4bnp4pahh6uqkbidpf3lrceoyagyndsylxvhfucd7wd4qacwwq',
    );
    expect(
      identity.cipherDigest,
      'sha256:ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0',
    );
  });

  test('HEAD has fixed canonical bytes and verifies manifest ciphertext', () {
    final ciphertext = Uint8List.fromList(utf8.encode('abc'));
    final identity = ManifestIdentity.fromCiphertext(ciphertext);
    const codec = VaultHeadCodec();
    final encoded = codec.encode(VaultHead(identity));

    expect(
      utf8.decode(encoded),
      '{"format":1,"manifest_cipher_digest":'
      '"sha256:ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0",'
      '"manifest_id":"xj4bnp4pahh6uqkbidpf3lrceoyagyndsylxvhfucd7wd4qacwwq"}',
    );
    final decoded = codec.decode(encoded);
    codec.verifyManifest(decoded, ciphertext);
    expect(
      () => codec.verifyManifest(decoded, Uint8List.fromList([1])),
      throwsA(isA<CorruptVaultDataFailure>()),
    );
  });

  test('HEAD rejects unknown, duplicate, and non-canonical fields', () {
    final identity = ManifestIdentity.fromCiphertext(Uint8List(0));
    const codec = VaultHeadCodec();
    final valid = utf8.decode(codec.encode(VaultHead(identity)));

    for (final invalid in [
      valid.replaceFirst('{', '{"extra":true,'),
      valid.replaceFirst('{', '{"format":1,'),
      valid.replaceFirst('{', '{ '),
    ]) {
      expect(
        () => codec.decode(Uint8List.fromList(utf8.encode(invalid))),
        throwsA(isA<VaultFailure>()),
      );
    }
  });

  test('initial manifest uses one millisecond UTC timestamp', () {
    final encoded = encodeInitialManifest(
      writerDeviceId: '00112233-4455-4677-8899-aabbccddeeff',
      createdAt: DateTime.parse('2026-09-20T12:34:56.789123+08:00'),
    );

    expect(
      utf8.decode(encoded),
      '{"created_at":"2026-09-20T04:34:56.789Z","entities":{},'
      '"format":1,"known_devices":{"00112233-4455-4677-8899-aabbccddeeff":'
      '{"last_seen_at":"2026-09-20T04:34:56.789Z"}},"parent_ids":[],'
      '"writer_device_id":"00112233-4455-4677-8899-aabbccddeeff"}',
    );
  });
}
