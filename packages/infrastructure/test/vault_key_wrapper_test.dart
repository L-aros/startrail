import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

void main() {
  const vaultUuid = '00112233-4455-6677-8899-aabbccddeeff';
  late SodiumSumo sodium;
  late VaultKeyWrapper wrapper;
  late SecureKey masterKey;
  late SecureKey kek;

  setUp(() async {
    sodium = await SodiumSumoInit.init();
    wrapper = VaultKeyWrapper(sodium);
    masterKey = sodium.secureRandom(32);
    kek = sodium.secureRandom(32);
  });

  tearDown(() {
    masterKey.dispose();
    kek.dispose();
  });

  test('wraps and unwraps a 32-byte VMK using header AD', () {
    final wrapped = wrapper.wrap(
      masterKey: masterKey,
      keyEncryptionKey: kek,
      vaultUuid: vaultUuid,
    );
    final unwrapped = wrapper.unwrap(
      ciphertext: wrapped.ciphertext,
      nonce: wrapped.nonce,
      keyEncryptionKey: kek,
      vaultUuid: vaultUuid,
    );
    addTearDown(unwrapped.dispose);

    expect(wrapped.nonce, hasLength(24));
    expect(wrapped.ciphertext, hasLength(48));
    expect(unwrapped, masterKey);
  });

  test('wrong KEK, changed UUID and tampering expose one failure', () {
    final wrapped = wrapper.wrap(
      masterKey: masterKey,
      keyEncryptionKey: kek,
      vaultUuid: vaultUuid,
    );
    final wrongKek = sodium.secureRandom(32);
    addTearDown(wrongKek.dispose);
    final tampered = Uint8List.fromList(wrapped.ciphertext)..[0] ^= 1;

    for (final attempt in [
      () => wrapper.unwrap(
        ciphertext: wrapped.ciphertext,
        nonce: wrapped.nonce,
        keyEncryptionKey: wrongKek,
        vaultUuid: vaultUuid,
      ),
      () => wrapper.unwrap(
        ciphertext: wrapped.ciphertext,
        nonce: wrapped.nonce,
        keyEncryptionKey: kek,
        vaultUuid: '10112233-4455-6677-8899-aabbccddeeff',
      ),
      () => wrapper.unwrap(
        ciphertext: tampered,
        nonce: wrapped.nonce,
        keyEncryptionKey: kek,
        vaultUuid: vaultUuid,
      ),
    ]) {
      expect(attempt, throwsA(isA<VaultAuthenticationFailure>()));
    }
  });
}
