import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';

import 'canonical_json.dart';
import 'manifest_identity.dart';

final class VaultHead {
  const VaultHead(this.manifest);

  final ManifestIdentity manifest;
}

final class VaultHeadCodec {
  const VaultHeadCodec();

  Uint8List encode(VaultHead head) => encodeCanonicalJson({
    'format': 1,
    'manifest_cipher_digest': head.manifest.cipherDigest,
    'manifest_id': head.manifest.manifestId,
  });

  VaultHead decode(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (!_equal(bytes, encodeCanonicalJson(decoded))) {
        throw const CorruptVaultDataFailure();
      }
      const keys = {'format', 'manifest_cipher_digest', 'manifest_id'};
      if (decoded.length != keys.length ||
          !decoded.keys.toSet().containsAll(keys)) {
        throw const UnsupportedVaultFormatFailure();
      }
      if (decoded['format'] != 1) {
        throw const UnsupportedVaultFormatFailure();
      }
      return VaultHead(
        ManifestIdentity.parse(
          manifestId: decoded['manifest_id'] as String,
          cipherDigest: decoded['manifest_cipher_digest'] as String,
        ),
      );
    } on VaultFailure {
      rethrow;
    } on Object {
      throw const CorruptVaultDataFailure();
    }
  }

  void verifyManifest(VaultHead head, Uint8List ciphertext) {
    if (!head.manifest.matchesCiphertext(ciphertext)) {
      throw const CorruptVaultDataFailure();
    }
  }
}

bool _equal(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
