import 'dart:typed_data';

import 'package:infrastructure/infrastructure.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

void main() {
  late SodiumSumo sodium;
  late PasswordKdf kdf;

  setUp(() async {
    sodium = await SodiumSumoInit.init();
    kdf = PasswordKdf(sodium);
  });

  test('uses the protocol Argon2id output size and is deterministic', () {
    final password = Int8List.fromList('test password'.codeUnits);
    final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final first = kdf.deriveKey(passwordBytes: password, salt: salt);
    final second = kdf.deriveKey(passwordBytes: password, salt: salt);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    expect(first.length, argon2idOutputBytes);
    expect(first, second);
    expect(password, isNot(everyElement(0)));
  });

  test('rejects a salt that is not exactly 16 bytes', () {
    expect(
      () => kdf.deriveKey(passwordBytes: Int8List(1), salt: Uint8List(15)),
      throwsArgumentError,
    );
  });
}
