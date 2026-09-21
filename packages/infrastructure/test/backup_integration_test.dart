import 'dart:io';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

void main() {
  late SodiumSumo sodium;
  late Directory sandbox;
  final password = Int8List.fromList('correct horse battery'.codeUnits);

  setUp(() async {
    sodium = await SodiumSumoInit.init();
    sandbox = await Directory.systemTemp.createTemp('startrail-backup-int-');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  Future<Directory> createVault() async {
    final vaultDir = Directory('${sandbox.path}/vault');
    final creator = await VaultCreator.initialize(
      durability: createDirectoryDurability(),
    );
    await creator.create(target: vaultDir, passwordBytes: password);
    return vaultDir;
  }

  Future<VaultSession> openAndSeed(Directory vaultDir) async {
    final session = await VaultSession.open(
      vault: vaultDir,
      passwordBytes: password,
      durability: createDirectoryDurability(),
    );
    final tag = Tag(
      id: const TagId('11111111-1111-4111-8111-111111111111'),
      name: '旅行',
      color: 0xff0000,
    );
    final blob = await session.entryStore.importBlob(
      mime: 'text/plain',
      bytes: Uint8List.fromList('attachment bytes'.codeUnits),
    );
    await session.entryStore.createEntry(
      EntryDraft(
        occurredAt: DateTime.utc(2026, 9, 21, 8),
        body: '去海边散步',
        mood: '开心',
        tags: [tag],
        attachments: [blob],
      ),
    );
    await session.entryStore.createEntry(
      EntryDraft(
        occurredAt: DateTime.utc(2026, 9, 20, 8),
        body: '读完一本书',
        mood: null,
        tags: const [],
        attachments: const [],
      ),
    );
    return session;
  }

  Future<List<String>> timelineBodies(VaultSession session) async =>
      (await session.entryStore.timeline()).map((entry) => entry.body).toList();

  Future<List<String>> tagNames(VaultSession session) async =>
      (await session.entryStore.listTags()).map((tag) => tag.name).toList();

  test(
    'backup with entries restores and rebuilds the index identically',
    () async {
      final vaultDir = await createVault();
      final session = await openAndSeed(vaultDir);
      final expectedBodies = await timelineBodies(session);
      final expectedTags = await tagNames(session);

      final backupPath = '${sandbox.path}/backup.stbackup';
      await session.backupStore.createBackup(
        targetPath: backupPath,
        passwordBytes: password,
      );

      final report = await session.backupStore.verifyBackup(
        backupPath: backupPath,
        passwordBytes: password,
      );
      expect(report.status, BackupVerificationStatus.ok);
      expect(report.objectCount, greaterThan(0));
      session.dispose();

      final restoredDir = Directory('${sandbox.path}/restored');
      final recovery = VaultBackupStore(
        sodium: sodium,
        durability: createDirectoryDurability(),
      );
      await recovery.restoreBackup(
        backupPath: backupPath,
        passwordBytes: password,
        targetPath: restoredDir.path,
        replaceExisting: false,
      );

      final restoredSession = await VaultSession.open(
        vault: restoredDir,
        passwordBytes: password,
        durability: createDirectoryDurability(),
      );
      expect(await timelineBodies(restoredSession), expectedBodies);
      expect(await tagNames(restoredSession), expectedTags);
      restoredSession.dispose();
    },
  );

  test('index is rebuilt from authenticated objects after deletion', () async {
    final vaultDir = await createVault();
    final session = await openAndSeed(vaultDir);
    final expectedBodies = await timelineBodies(session);
    final expectedTags = await tagNames(session);
    session.dispose();

    final separator = Platform.pathSeparator;
    final index = File(
      '${vaultDir.path}$separator${'local'}$separator${'index.db'}',
    );
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('${index.path}$suffix');
      if (await file.exists()) await file.delete();
    }

    final reopened = await VaultSession.open(
      vault: vaultDir,
      passwordBytes: password,
      durability: createDirectoryDurability(),
    );
    expect(await timelineBodies(reopened), expectedBodies);
    expect(await tagNames(reopened), expectedTags);
    reopened.dispose();
  });
}
