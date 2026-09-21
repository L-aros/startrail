import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  const codec = ManifestV1Codec();
  const deviceId = '99999999-9999-4999-8999-999999999999';
  const entryId = '11111111-1111-4111-8111-111111111111';
  const objectId = 'abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrst';
  final createdAt = DateTime.utc(2026, 9, 21, 12, 34, 56, 789);

  test('initial manifest decodes to an empty structure', () {
    final bytes = encodeInitialManifest(
      writerDeviceId: deviceId,
      createdAt: createdAt,
    );
    final manifest = codec.decode(bytes);
    expect(manifest.entities, isEmpty);
    expect(manifest.parentIds, isEmpty);
    expect(manifest.writerDeviceId, deviceId);
    expect(manifest.createdAt, createdAt);
    expect(manifest.knownDevices.keys, [deviceId]);
  });

  test('roundtrip preserves entities and parents', () {
    final manifest = ManifestV1(
      entities: {
        entryId: [objectId],
      },
      parentIds: [objectId],
      writerDeviceId: deviceId,
      createdAt: createdAt,
      knownDevices: {deviceId: createdAt},
    );

    final decoded = codec.decode(codec.encode(manifest));
    expect(decoded.entities[entryId], [objectId]);
    expect(decoded.parentIds, [objectId]);
    expect(decoded.writerDeviceId, deviceId);
    expect(decoded.knownDevices[deviceId], createdAt);
  });

  test('rejects missing field', () {
    final bytes = encodeInitialManifest(
      writerDeviceId: deviceId,
      createdAt: createdAt,
    );
    final text = String.fromCharCodes(bytes).replaceFirst('"format":1,', '');
    expect(
      () => codec.decode(Uint8List.fromList(text.codeUnits)),
      throwsA(isA<UnsupportedVaultFormatFailure>()),
    );
  });

  test('validateManifestV1 accepts a well-formed manifest', () {
    final bytes = encodeInitialManifest(
      writerDeviceId: deviceId,
      createdAt: createdAt,
    );
    expect(() => validateManifestV1(bytes), returnsNormally);
  });
}
