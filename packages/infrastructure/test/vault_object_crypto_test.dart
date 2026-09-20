import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

void main() {
  late VaultObjectCrypto crypto;
  late SecureKey masterKey;
  final vaultUuid = Uint8List.fromList(List<int>.generate(16, (i) => i));

  setUp(() async {
    crypto = await VaultObjectCrypto.initialize();
    masterKey = crypto.generateMasterKey();
  });

  tearDown(() => masterKey.dispose());

  test('encrypts and decrypts with fresh nonces', () {
    final plaintext = Uint8List.fromList([1, 2, 3, 4]);
    final first = crypto.encrypt(
      plaintext: plaintext,
      masterKey: masterKey,
      vaultUuid: vaultUuid,
      type: VaultObjectType.entry,
      schemaVersion: 1,
    );
    final second = crypto.encrypt(
      plaintext: plaintext,
      masterKey: masterKey,
      vaultUuid: vaultUuid,
      type: VaultObjectType.entry,
      schemaVersion: 1,
    );

    expect(first, isNot(second));
    expect(
      crypto.decrypt(
        envelopeBytes: first,
        masterKey: masterKey,
        vaultUuid: vaultUuid,
      ),
      plaintext,
    );
  });

  test('tampering, wrong key, and wrong vault id expose one failure', () {
    final encrypted = crypto.encrypt(
      plaintext: Uint8List.fromList([7, 8, 9]),
      masterKey: masterKey,
      vaultUuid: vaultUuid,
      type: VaultObjectType.manifest,
      schemaVersion: 1,
    );
    final tampered = Uint8List.fromList(encrypted)..[encrypted.length - 1] ^= 1;
    final wrongKey = crypto.generateMasterKey();
    addTearDown(wrongKey.dispose);

    for (final attempt in [
      () => crypto.decrypt(
        envelopeBytes: tampered,
        masterKey: masterKey,
        vaultUuid: vaultUuid,
      ),
      () => crypto.decrypt(
        envelopeBytes: encrypted,
        masterKey: wrongKey,
        vaultUuid: vaultUuid,
      ),
      () => crypto.decrypt(
        envelopeBytes: encrypted,
        masterKey: masterKey,
        vaultUuid: Uint8List(16),
      ),
    ]) {
      expect(attempt, throwsA(isA<VaultAuthenticationFailure>()));
    }
  });

  test(
    'additional data is stable and binds type and schema as envelope bytes',
    () {
      final ad = objectAdditionalData(
        vaultUuid: vaultUuid,
        type: VaultObjectType.blob,
        schemaVersion: 0x1234,
      );

      expect(ad.sublist(ad.length - 3), [5, 0x12, 0x34]);
    },
  );
}
