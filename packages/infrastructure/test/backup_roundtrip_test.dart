import 'dart:io';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

void main() {
  late SodiumSumo sodium;
  late Directory sandbox;
  late Directory vault;
  late String vaultUuid;
  late String deviceId;
  late String backupPath;
  late Uint8List backupBytes;

  final password = Int8List.fromList('correct horse battery'.codeUnits);
  final wrongPassword = Int8List.fromList('wrong password'.codeUnits);

  setUp(() async {
    sodium = await SodiumSumoInit.init();
    sandbox = await Directory.systemTemp.createTemp('startrail-backup-');
    vault = Directory('${sandbox.path}/vault');
    final creator = await VaultCreator.initialize(
      durability: createDirectoryDurability(),
    );
    final created = await creator.create(
      target: vault,
      passwordBytes: password,
    );
    vaultUuid = created.vaultUuid;
    deviceId = created.deviceUuid;

    backupPath = '${sandbox.path}/backup.stbackup';
    final backupCreator = BackupCreator(
      sodium: sodium,
      vault: vault,
      vaultUuid: uuidBytes(vaultUuid),
      deviceId: deviceId,
      durability: createDirectoryDurability(),
    );
    final summary = await backupCreator.createBackup(
      targetPath: backupPath,
      passwordBytes: password,
    );
    expect(summary.vaultUuid, vaultUuid);
    expect(summary.fileCount, 3); // vault.header, HEAD, initial manifest
    expect(summary.objectCount, 0);
    backupBytes = await File(backupPath).readAsBytes();
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  Future<String> writeVariant(String name, Uint8List bytes) async {
    final path = '${sandbox.path}/$name';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  test('verifies an authentic backup as ok', () async {
    final report = await BackupVerifier(
      sodium,
    ).verify(backupPath: backupPath, passwordBytes: password);
    expect(report.status, BackupVerificationStatus.ok);
    expect(report.vaultUuid, vaultUuid);
    expect(report.fileCount, 3);
    expect(report.objectCount, 0);
    expect(report.rootDigest, startsWith('sha256:'));
  });

  test('reports wrongPassword without touching any Vault', () async {
    final report = await BackupVerifier(
      sodium,
    ).verify(backupPath: backupPath, passwordBytes: wrongPassword);
    expect(report.status, BackupVerificationStatus.wrongPassword);
  });

  test('reports tampered when a carried file byte is flipped', () async {
    final tampered = Uint8List.fromList(backupBytes)
      ..[backupBytes.length - 1] ^= 1;
    final report = await BackupVerifier(sodium).verify(
      backupPath: await writeVariant('tampered.stbackup', tampered),
      passwordBytes: password,
    );
    expect(report.status, BackupVerificationStatus.tampered);
  });

  test('reports tampered when the sealed manifest is flipped', () async {
    final offset = _manifestCiphertextOffset(backupBytes);
    final tampered = Uint8List.fromList(backupBytes)..[offset] ^= 1;
    final report = await BackupVerifier(sodium).verify(
      backupPath: await writeVariant('manifest-tampered.stbackup', tampered),
      passwordBytes: password,
    );
    expect(report.status, BackupVerificationStatus.tampered);
  });

  test('reports corrupt when truncated', () async {
    final truncated = Uint8List.sublistView(
      backupBytes,
      0,
      backupBytes.length - 8,
    );
    final report = await BackupVerifier(sodium).verify(
      backupPath: await writeVariant('truncated.stbackup', truncated),
      passwordBytes: password,
    );
    expect(report.status, BackupVerificationStatus.corrupt);
  });

  test('reports unsupported for a wrong magic', () async {
    final wrong = Uint8List.fromList(backupBytes)..[0] = 0x00;
    final report = await BackupVerifier(sodium).verify(
      backupPath: await writeVariant('bad-magic.stbackup', wrong),
      passwordBytes: password,
    );
    expect(report.status, BackupVerificationStatus.unsupported);
  });

  test('restores to a clean directory byte-for-byte and unlocks', () async {
    final restored = Directory('${sandbox.path}/restored');
    final restorer = BackupRestorer(
      sodium: sodium,
      durability: createDirectoryDurability(),
    );
    await restorer.restore(
      backupPath: backupPath,
      passwordBytes: password,
      targetPath: restored.path,
      replaceExisting: false,
    );

    await _expectVaultFilesEqual(vault, restored);

    final unlocker = await VaultUnlocker.initialize();
    final unlocked = await unlocker.unlock(
      vault: restored,
      passwordBytes: password,
    );
    expect(unlocked.vaultUuid, vaultUuid);
    unlocked.dispose();
  });

  test(
    'refuses to overwrite a non-empty target without confirmation',
    () async {
      final occupied = Directory('${sandbox.path}/occupied');
      await occupied.create();
      await File('${occupied.path}/keep.txt').writeAsString('keep');

      final restorer = BackupRestorer(
        sodium: sodium,
        durability: createDirectoryDurability(),
      );
      await expectLater(
        restorer.restore(
          backupPath: backupPath,
          passwordBytes: password,
          targetPath: occupied.path,
          replaceExisting: false,
        ),
        throwsA(isA<BackupTargetOccupied>()),
      );
      expect(await File('${occupied.path}/keep.txt').readAsString(), 'keep');
    },
  );

  test('wrong password leaves the target untouched', () async {
    final target = Directory('${sandbox.path}/untouched');
    final restorer = BackupRestorer(
      sodium: sodium,
      durability: createDirectoryDurability(),
    );
    await expectLater(
      restorer.restore(
        backupPath: backupPath,
        passwordBytes: wrongPassword,
        targetPath: target.path,
        replaceExisting: false,
      ),
      throwsA(isA<VaultAuthenticationFailure>()),
    );
    expect(await target.exists(), isFalse);
  });
}

int _manifestCiphertextOffset(Uint8List bytes) {
  final headerLength = ByteData.sublistView(bytes).getUint32(7);
  return backupHeaderPrefixLength + headerLength + backupManifestNonceBytes + 8;
}

Future<void> _expectVaultFilesEqual(Directory a, Directory b) async {
  final separator = Platform.pathSeparator;
  for (final relative in ['vault.header', 'HEAD']) {
    final fa = File('${a.path}$separator$relative');
    final fb = File('${b.path}$separator$relative');
    expect(await fa.readAsBytes(), await fb.readAsBytes(), reason: relative);
  }
  for (final sub in ['objects', 'manifests']) {
    final dirA = Directory('${a.path}$separator$sub');
    final dirB = Directory('${b.path}$separator$sub');
    final namesA = await _relativeFilePaths(dirA);
    final namesB = await _relativeFilePaths(dirB);
    expect(namesA, namesB, reason: sub);
    for (final name in namesA) {
      final fa = File(
        '${dirA.path}$separator${name.replaceAll('/', separator)}',
      );
      final fb = File(
        '${dirB.path}$separator${name.replaceAll('/', separator)}',
      );
      expect(
        await fa.readAsBytes(),
        await fb.readAsBytes(),
        reason: '$sub/$name',
      );
    }
  }
}

Future<List<String>> _relativeFilePaths(Directory dir) async {
  final result = <String>[];
  if (!await dir.exists()) return result;
  final prefix = dir.path;
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File) {
      result.add(
        entity.path.substring(prefix.length + 1).replaceAll('\\', '/'),
      );
    }
  }
  result.sort();
  return result;
}
