import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _base32Alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

/// Computes the immutable content ID of an encrypted object: the lowercase
/// base32 (no padding) encoding of SHA-256 over the ciphertext envelope bytes.
/// Always 52 characters.
String objectIdFromCiphertext(Uint8List ciphertext) {
  if (ciphertext.isEmpty) {
    throw ArgumentError.value(ciphertext, 'ciphertext', 'empty');
  }
  final digest = Uint8List.fromList(sha256.convert(ciphertext).bytes);
  final id = _encodeBase32(digest);
  if (!RegExp(r'^[a-z2-7]{52}$').hasMatch(id)) {
    throw StateError('object id encoding invariant violated');
  }
  return id;
}

/// Decodes a 52-char base32 id back into its 32-byte digest, for cross-checks.
Uint8List objectIdDigest(String objectId) {
  if (!RegExp(r'^[a-z2-7]{52}$').hasMatch(objectId)) {
    throw ArgumentError.value(objectId, 'objectId', 'not a 52-char base32 id');
  }
  var buffer = 0;
  var bits = 0;
  final output = <int>[];
  for (final codeUnit in objectId.codeUnits) {
    final value = _base32Alphabet.indexOf(String.fromCharCode(codeUnit));
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      output.add((buffer >> bits) & 0xff);
    }
  }
  if (output.length != 32) {
    throw ArgumentError.value(objectId, 'objectId', 'invalid length');
  }
  return Uint8List.fromList(output);
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
