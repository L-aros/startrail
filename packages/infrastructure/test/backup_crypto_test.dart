import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

void main() {
  late SodiumSumo sodium;
  late BackupCrypto crypto;
  late SecureKey kek;

  const vaultUuid = '00112233-4455-6677-8899-aabbccddeeff';
  const otherVaultUuid = '11223344-5566-7788-99aa-bbccddeeff00';

  setUp(() async {
    sodium = await SodiumSumoInit.init();
    crypto = BackupCrypto(sodium);
    kek = PasswordKdf(sodium).deriveKey(
      passwordBytes: Int8List.fromList(utf8.encode('correct horse battery')),
      salt: Uint8List(16),
    );
  });

  tearDown(() => kek.dispose());

  test('backup key wraps and unwraps round-trip under the KEK', () {
    final backupKey = crypto.generateBackupKey();
    addTearDown(backupKey.dispose);
    final wrapped = crypto.wrapBackupKey(
      backupKey: backupKey,
      keyEncryptionKey: kek,
      vaultUuid: vaultUuid,
    );
    final unwrapped = crypto.unwrapBackupKey(
      ciphertext: wrapped.ciphertext,
      nonce: wrapped.nonce,
      keyEncryptionKey: kek,
      vaultUuid: vaultUuid,
    );
    addTearDown(unwrapped.dispose);

    final original = backupKey.runUnlockedSync(Uint8List.fromList);
    final roundTripped = unwrapped.runUnlockedSync(Uint8List.fromList);
    expect(roundTripped, original);
  });

  test('unwrap fails with a wrong password-derived key', () {
    final backupKey = crypto.generateBackupKey();
    addTearDown(backupKey.dispose);
    final wrapped = crypto.wrapBackupKey(
      backupKey: backupKey,
      keyEncryptionKey: kek,
      vaultUuid: vaultUuid,
    );
    final wrongKek = PasswordKdf(sodium).deriveKey(
      passwordBytes: Int8List.fromList(utf8.encode('wrong')),
      salt: Uint8List(16),
    );
    addTearDown(wrongKek.dispose);

    expect(
      () => crypto.unwrapBackupKey(
        ciphertext: wrapped.ciphertext,
        nonce: wrapped.nonce,
        keyEncryptionKey: wrongKek,
        vaultUuid: vaultUuid,
      ),
      throwsA(isA<VaultAuthenticationFailure>()),
    );
  });

  test('unwrap fails when the vault uuid additional data is swapped', () {
    final backupKey = crypto.generateBackupKey();
    addTearDown(backupKey.dispose);
    final wrapped = crypto.wrapBackupKey(
      backupKey: backupKey,
      keyEncryptionKey: kek,
      vaultUuid: vaultUuid,
    );

    expect(
      () => crypto.unwrapBackupKey(
        ciphertext: wrapped.ciphertext,
        nonce: wrapped.nonce,
        keyEncryptionKey: kek,
        vaultUuid: otherVaultUuid,
      ),
      throwsA(isA<VaultAuthenticationFailure>()),
    );
  });

  test('manifest seals and opens, and a flipped byte is rejected', () {
    final backupKey = crypto.generateBackupKey();
    addTearDown(backupKey.dispose);
    final plaintext = Uint8List.fromList(utf8.encode('{"hello":"world"}'));

    final sealed = crypto.sealManifest(
      plaintext: plaintext,
      backupKey: backupKey,
      vaultUuid: vaultUuid,
    );
    expect(
      crypto.openManifest(
        nonce: sealed.nonce,
        ciphertext: sealed.ciphertext,
        backupKey: backupKey,
        vaultUuid: vaultUuid,
      ),
      plaintext,
    );

    final tampered = Uint8List.fromList(sealed.ciphertext)..[0] ^= 1;
    expect(
      () => crypto.openManifest(
        nonce: sealed.nonce,
        ciphertext: tampered,
        backupKey: backupKey,
        vaultUuid: vaultUuid,
      ),
      throwsA(isA<SodiumException>()),
    );
  });

  test('additional data is domain-separated from the vault key wrapper', () {
    expect(
      backupKeyAdditionalData(vaultUuid),
      isNot(headerAdditionalData(vaultUuid)),
    );
    expect(
      backupManifestAdditionalData(vaultUuid),
      isNot(headerAdditionalData(vaultUuid)),
    );
  });
}
