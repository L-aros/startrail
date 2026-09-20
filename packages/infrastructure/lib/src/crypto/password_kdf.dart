import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

const argon2idSaltBytes = 16;
const argon2idOutputBytes = 32;
const argon2idMemoryBytes = 64 * 1024 * 1024;
const argon2idIterations = 3;

final class PasswordKdf {
  PasswordKdf(this._sodium);

  final SodiumSumo _sodium;

  SecureKey deriveKey({
    required Int8List passwordBytes,
    required Uint8List salt,
  }) {
    if (salt.length != argon2idSaltBytes) {
      throw ArgumentError.value(salt.length, 'salt.length');
    }
    final passwordCopy = Int8List.fromList(passwordBytes);
    try {
      return _sodium.crypto.pwhash(
        outLen: argon2idOutputBytes,
        password: passwordCopy,
        salt: salt,
        opsLimit: argon2idIterations,
        memLimit: argon2idMemoryBytes,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
    } finally {
      passwordCopy.fillRange(0, passwordCopy.length, 0);
    }
  }
}
