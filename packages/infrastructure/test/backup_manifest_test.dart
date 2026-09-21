import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  const codec = BackupManifestCodec();
  const vaultUuid = '00112233-4455-6677-8899-aabbccddeeff';
  const deviceId = '99999999-9999-4999-8999-999999999999';
  const objectId = 'abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrst';
  final createdAt = DateTime.utc(2026, 9, 21, 12, 34, 56, 789);
  final digest = 'sha256:${'A' * 43}';

  BackupManifest manifest(List<BackupFileEntry> files) => BackupManifest(
    vaultUuid: vaultUuid,
    createdAt: createdAt,
    deviceId: deviceId,
    files: files,
  );

  test('round trips files with object counts and total bytes', () {
    final source = manifest([
      BackupFileEntry(path: 'vault.header', size: 100, digest: digest),
      BackupFileEntry(path: 'HEAD', size: 50, digest: digest),
      BackupFileEntry(path: 'objects/aa/$objectId', size: 7, digest: digest),
      BackupFileEntry(path: 'manifests/$objectId', size: 9, digest: digest),
    ]);
    final decoded = codec.decode(codec.encode(source));
    expect(decoded.vaultUuid, vaultUuid);
    expect(decoded.deviceId, deviceId);
    expect(decoded.createdAt, createdAt);
    expect(decoded.files.map((f) => f.path), source.files.map((f) => f.path));
    expect(decoded.objectCount, 1);
    expect(decoded.totalBytes, 166);
  });

  test('rejects paths outside the authoritative whitelist', () {
    for (final badPath in [
      '../evil',
      'vault.header/../HEAD',
      'local/index.db',
      'objects/short',
      'objects/aa/not-base32',
      'manifests/abc',
      'HEAD/extra',
      'objects/aa/$objectId/extra',
    ]) {
      final m = manifest([
        BackupFileEntry(path: badPath, size: 1, digest: digest),
      ]);
      expect(
        () => codec.encode(m),
        throwsA(isA<FormatException>()),
        reason: 'path "$badPath" must be rejected',
      );
    }
  });

  test('rejects a malformed digest and a negative size', () {
    expect(
      () => codec.encode(
        manifest([
          BackupFileEntry(path: 'HEAD', size: 1, digest: 'not-a-digest'),
        ]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => codec.encode(
        manifest([BackupFileEntry(path: 'HEAD', size: -1, digest: digest)]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unknown fields on decode', () {
    final bytes = codec.encode(
      manifest([BackupFileEntry(path: 'HEAD', size: 1, digest: digest)]),
    );
    final text = String.fromCharCodes(bytes).replaceFirst(
      '"device_id":"$deviceId",',
      '"device_id":"$deviceId","extra":true,',
    );
    expect(
      () => codec.decode(Uint8List.fromList(text.codeUnits)),
      throwsA(isA<UnsupportedVaultFormatFailure>()),
    );
  });
}
