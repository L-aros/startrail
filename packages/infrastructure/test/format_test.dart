import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  group('canonical JSON', () {
    test('sorts keys recursively without whitespace', () {
      final encoded = encodeCanonicalJson({
        'z': 1,
        'a': {'d': 4, 'b': 2},
        'list': [
          {'y': true, 'x': false},
        ],
      });

      expect(
        utf8.decode(encoded),
        r'{"a":{"b":2,"d":4},"list":[{"x":false,"y":true}],"z":1}',
      );
    });

    test('rejects values outside the JSON data model', () {
      expect(
        () => encodeCanonicalJson(DateTime.utc(2026)),
        throwsArgumentError,
      );
    });
  });

  group('object envelope v1', () {
    const codec = ObjectEnvelopeCodec();
    final nonce = Uint8List.fromList(List<int>.generate(24, (index) => index));
    final ciphertext = Uint8List.fromList(List<int>.filled(16, 0xa5));

    test('round trips the binary protocol using big-endian schema', () {
      final bytes = codec.encode(
        ObjectEnvelope(
          type: VaultObjectType.manifest,
          schemaVersion: 0x1234,
          nonce: nonce,
          ciphertext: ciphertext,
        ),
      );

      expect(ascii.decode(bytes.sublist(0, 4)), 'STOB');
      expect(bytes.sublist(4, 8), [1, 4, 0x12, 0x34]);
      final decoded = codec.decode(bytes);
      expect(decoded.type, VaultObjectType.manifest);
      expect(decoded.schemaVersion, 0x1234);
      expect(decoded.nonce, nonce);
      expect(decoded.ciphertext, ciphertext);
    });

    test('hard fails on truncation, unknown version, and unknown type', () {
      final valid = codec.encode(
        ObjectEnvelope(
          type: VaultObjectType.entry,
          schemaVersion: 1,
          nonce: nonce,
          ciphertext: ciphertext,
        ),
      );
      expect(
        () => codec.decode(Uint8List(47)),
        throwsA(isA<CorruptVaultDataFailure>()),
      );
      expect(
        () => codec.decode(Uint8List.fromList(valid)..[4] = 2),
        throwsA(isA<UnsupportedVaultFormatFailure>()),
      );
      expect(
        () => codec.decode(Uint8List.fromList(valid)..[5] = 255),
        throwsA(isA<UnsupportedVaultFormatFailure>()),
      );
    });
  });
}
