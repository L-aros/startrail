import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

/// Encrypts and decrypts the local index's searchable/tag text fields with the
/// index key derived from the Vault Master Key (ADR-0011 context `STIDX001`).
///
/// Ciphertext layout is `nonce(24) || XChaCha20-Poly1305(plaintext)`, stored in
/// a single BLOB column. Nonces are random, so the database `UNIQUE` constraint
/// never doubles as a de-duplication mechanism; uniqueness is enforced at the
/// application layer after decryption.
final class SearchCipher {
  SearchCipher(this._sodium, this._indexKey);

  final SodiumSumo _sodium;
  final SecureKey _indexKey;

  Uint8List encrypt(String plaintext) {
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    final nonce = _sodium.randombytes.buf(aead.nonceBytes);
    final ciphertext = aead.encrypt(
      message: Uint8List.fromList(utf8.encode(plaintext)),
      nonce: nonce,
      key: _indexKey,
    );
    return Uint8List.fromList([...nonce, ...ciphertext]);
  }

  String decrypt(Uint8List blob) {
    final aead = _sodium.crypto.aeadXChaCha20Poly1305IETF;
    if (blob.length <= aead.nonceBytes) {
      throw const FormatException('search ciphertext too short');
    }
    final nonce = Uint8List.sublistView(blob, 0, aead.nonceBytes);
    final ciphertext = Uint8List.sublistView(blob, aead.nonceBytes);
    final plaintext = aead.decrypt(
      cipherText: ciphertext,
      nonce: nonce,
      key: _indexKey,
    );
    return utf8.decode(plaintext);
  }
}
