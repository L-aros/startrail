import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

void main() {
  late SodiumSumo sodium;
  late Directory sandbox;

  setUp(() async {
    sodium = await SodiumSumoInit.init();
    sandbox = Directory.systemTemp.createTempSync('startrail-entry-test-');
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  Future<_Session> openSession() async {
    final vaultDir = Directory('${sandbox.path}/vault');
    final password = Int8List.fromList(utf8.encode('correct horse battery'));
    final creator = await VaultCreator.initialize(
      durability: createDirectoryDurability(),
    );
    final created = await creator.create(
      target: vaultDir,
      passwordBytes: password,
    );
    final unlocker = await VaultUnlocker.initialize();
    final unlocked = await unlocker.unlock(
      vault: vaultDir,
      passwordBytes: password,
    );
    final headBytes = await File(
      '${vaultDir.path}${Platform.pathSeparator}HEAD',
    ).readAsBytes();
    final head = const VaultHeadCodec().decode(headBytes);
    final manifest = const ManifestV1Codec().decode(unlocked.manifestPlaintext);
    final factory = IndexDatabaseFactory(
      sodium,
      durability: createDirectoryDurability(),
    );
    final index = await factory.create(
      '${vaultDir.path}${Platform.pathSeparator}local'
      '${Platform.pathSeparator}index.db',
      masterKey: unlocked.masterKey,
      manifestId: head.manifest.manifestId,
    );
    final store = VaultEntryStore(
      sodium: sodium,
      vault: vaultDir,
      vaultUuid: uuidBytes(unlocked.vaultUuid),
      masterKey: unlocked.masterKey,
      deviceId: created.deviceUuid,
      manifest: manifest,
      manifestId: head.manifest.manifestId,
      index: index,
      durability: createDirectoryDurability(),
    );
    return _Session(unlocked, index, store);
  }

  EntryDraft draft(String body) => EntryDraft(
    occurredAt: DateTime.utc(2026, 9, 21, 8),
    body: body,
    mood: null,
    tags: const [],
    attachments: const [],
  );

  test('create, list, update, search and delete entries', () async {
    final session = await openSession();
    addTearDown(session.dispose);

    final first = await session.store.createEntry(draft('去海边散步'));
    final second = await session.store.createEntry(draft('读完一本书'));

    var timeline = await session.store.timeline();
    expect(timeline.map((e) => e.body), containsAll(['去海边散步', '读完一本书']));

    final edited = await session.store.updateEntry(first.id, 1, draft('去山里徒步'));
    expect(edited.revision, 2);

    timeline = await session.store.timeline();
    expect(timeline.map((e) => e.body), isNot(contains('去海边散步')));
    expect(timeline.map((e) => e.body), contains('去山里徒步'));

    final hits = await session.store.searchEntries('徒步');
    expect(hits.map((e) => e.body), contains('去山里徒步'));

    await session.store.deleteEntry(second.id, 1);
    timeline = await session.store.timeline();
    expect(timeline.map((e) => e.id), isNot(contains(second.id)));
  });

  test('timeline orders by occurred_at descending', () async {
    final session = await openSession();
    addTearDown(session.dispose);

    final older = EntryDraft(
      occurredAt: DateTime.utc(2026, 1, 1),
      body: 'older',
      mood: null,
      tags: const [],
      attachments: const [],
    );
    final newer = EntryDraft(
      occurredAt: DateTime.utc(2026, 6, 1),
      body: 'newer',
      mood: null,
      tags: const [],
      attachments: const [],
    );
    await session.store.createEntry(older);
    await session.store.createEntry(newer);

    final timeline = await session.store.timeline();
    expect(timeline.first.body, 'newer');
    expect(timeline.last.body, 'older');
  });

  test('rejects update and delete with a stale revision', () async {
    final session = await openSession();
    addTearDown(session.dispose);

    final entry = await session.store.createEntry(draft('原始'));
    await session.store.updateEntry(entry.id, 1, draft('第一次修改'));

    expect(
      () => session.store.updateEntry(entry.id, 1, draft('过期修改')),
      throwsA(isA<EntryRevisionConflict>()),
    );
    expect(
      () => session.store.deleteEntry(entry.id, 1),
      throwsA(isA<EntryRevisionConflict>()),
    );
  });

  test('tags are persisted and deduplicated by id', () async {
    final session = await openSession();
    addTearDown(session.dispose);

    final tagged = EntryDraft(
      occurredAt: DateTime.utc(2026, 9, 21),
      body: '有标签',
      mood: null,
      tags: [
        Tag(
          id: const TagId('22222222-2222-4222-8222-222222222222'),
          name: '旅行',
          color: 1,
        ),
      ],
      attachments: const [],
    );
    await session.store.createEntry(tagged);

    final tags = await session.store.listTags();
    expect(tags.map((t) => t.name), contains('旅行'));
  });
}

final class _Session {
  _Session(this.unlocked, this.index, this.store);

  final UnlockedVault unlocked;
  final EncryptedIndexDatabase index;
  final VaultEntryStore store;

  void dispose() {
    store.dispose();
    index.close();
    unlocked.dispose();
  }
}
