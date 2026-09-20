import 'dart:io';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory vault;
  final password = Int8List.fromList('correct password'.codeUnits);

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('startrail-unlock-');
    vault = Directory('${sandbox.path}${Platform.pathSeparator}vault');
    final creator = await VaultCreator.initialize(
      durability: createDirectoryDurability(),
      clock: () => DateTime.utc(2026, 9, 20),
    );
    await creator.create(target: vault, passwordBytes: password);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('unlocks and clears sensitive session state on dispose', () async {
    final unlocker = await VaultUnlocker.initialize();
    final session = await unlocker.unlock(
      vault: vault,
      passwordBytes: password,
    );

    expect(session.manifestPlaintext, isNotEmpty);
    session.dispose();
    expect(session.manifestPlaintext, everyElement(0));
    session.dispose();
  });

  test(
    'wrong password exposes only the stable authentication failure',
    () async {
      final unlocker = await VaultUnlocker.initialize();

      await expectLater(
        unlocker.unlock(
          vault: vault,
          passwordBytes: Int8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<VaultAuthenticationFailure>()),
      );
    },
  );

  test('tampered manifest is rejected before plaintext is returned', () async {
    final head = const VaultHeadCodec().decode(
      await File('${vault.path}${Platform.pathSeparator}HEAD').readAsBytes(),
    );
    final manifest = File(
      '${vault.path}${Platform.pathSeparator}manifests'
      '${Platform.pathSeparator}${head.manifest.manifestId}',
    );
    final bytes = await manifest.readAsBytes()
      ..[40] ^= 1;
    await manifest.writeAsBytes(bytes, flush: true);
    final unlocker = await VaultUnlocker.initialize();

    await expectLater(
      unlocker.unlock(vault: vault, passwordBytes: password),
      throwsA(isA<CorruptVaultDataFailure>()),
    );
  });
}
