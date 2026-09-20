import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:domain/domain.dart';

const _base32Alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

final class ManifestIdentity {
  ManifestIdentity._(this.digestBytes)
    : manifestId = _encodeBase32(digestBytes),
      cipherDigest =
          'sha256:${base64Url.encode(digestBytes).replaceAll('=', '')}';

  factory ManifestIdentity.fromCiphertext(Uint8List ciphertext) =>
      ManifestIdentity._(Uint8List.fromList(sha256.convert(ciphertext).bytes));

  final Uint8List digestBytes;
  final String manifestId;
  final String cipherDigest;

  static ManifestIdentity parse({
    required String manifestId,
    required String cipherDigest,
  }) {
    if (!cipherDigest.startsWith('sha256:')) {
      throw const UnsupportedVaultFormatFailure();
    }
    final digestText = cipherDigest.substring(7);
    if (digestText.contains('=')) throw const CorruptVaultDataFailure();
    try {
      final padding = '=' * ((4 - digestText.length % 4) % 4);
      final digest = Uint8List.fromList(
        base64Url.decode('$digestText$padding'),
      );
      if (digest.length != 32) throw const FormatException();
      final identity = ManifestIdentity._(digest);
      if (identity.manifestId != manifestId ||
          identity.cipherDigest != cipherDigest) {
        throw const CorruptVaultDataFailure();
      }
      return identity;
    } on VaultFailure {
      rethrow;
    } on Object {
      throw const CorruptVaultDataFailure();
    }
  }

  bool matchesCiphertext(Uint8List ciphertext) =>
      ManifestIdentity.fromCiphertext(ciphertext).manifestId == manifestId;
}

String _encodeBase32(Uint8List bytes) {
  final output = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      output.write(_base32Alphabet[(buffer >> bits) & 31]);
    }
  }
  if (bits > 0) output.write(_base32Alphabet[(buffer << (5 - bits)) & 31]);
  return output.toString();
}
