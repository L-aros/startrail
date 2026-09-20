import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  final valid = encodeInitialManifest(
    writerDeviceId: '00112233-4455-4677-8899-aabbccddeeff',
    createdAt: DateTime.utc(2026, 9, 20),
  );

  test('accepts the canonical initial manifest', () {
    expect(() => validateManifestV1(valid), returnsNormally);
  });

  test('rejects unknown, duplicate, non-canonical and unknown format data', () {
    final json = utf8.decode(valid);
    for (final invalid in [
      json.replaceFirst('{', '{"extra":true,'),
      json.replaceFirst('{', '{"format":1,'),
      json.replaceFirst('{', '{ '),
      json.replaceFirst('"format":1', '"format":2'),
    ]) {
      expect(
        () => validateManifestV1(Uint8List.fromList(utf8.encode(invalid))),
        throwsA(isA<VaultFailure>()),
      );
    }
  });
}
