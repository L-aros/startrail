import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../crypto/vault_object_crypto.dart';
import '../format/entry_object.dart';
import '../format/head.dart';
import '../format/manifest_codec.dart';
import '../format/manifest_identity.dart';
import '../format/object_id.dart';
import '../storage/atomic_file_writer.dart';
import '../storage/index_database.dart';
import '../storage/search_cipher.dart';

/// Infrastructure adapter implementing [EntryStore] over an unlocked Vault.
///
/// Every mutation follows the ADR-0016 transaction order: write the encrypted
/// entry/tombstone object, publish a new manifest with a parent chain, atomically
/// replace HEAD, then update the derived SQLCipher index in a single step.
final class VaultEntryStore implements EntryStore {
  VaultEntryStore({
    required SodiumSumo sodium,
    required Directory vault,
    required Uint8List vaultUuid,
    required SecureKey masterKey,
    required String deviceId,
    required ManifestV1 manifest,
    required String manifestId,
    required EncryptedIndexDatabase index,
    required DirectoryDurability durability,
    Random? random,
    DateTime Function()? clock,
  }) : _sodium = sodium,
       _vault = vault,
       _vaultUuid = Uint8List.fromList(vaultUuid),
       _masterKey = masterKey,
       _deviceId = deviceId,
       _manifest = manifest,
       _manifestId = manifestId,
       _index = index,
       _durability = durability,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now,
       _objectCrypto = VaultObjectCrypto(sodium),
       _indexKey = IndexKeyDeriver(sodium).derive(masterKey) {
    if (vaultUuid.length != 16) {
      throw ArgumentError.value(vaultUuid.length, 'vaultUuid.length');
    }
  }

  final SodiumSumo _sodium;
  final Directory _vault;
  final Uint8List _vaultUuid;
  final SecureKey _masterKey;
  final String _deviceId;
  ManifestV1 _manifest;
  String _manifestId;
  final EncryptedIndexDatabase _index;
  final DirectoryDurability _durability;
  final Random _random;
  final DateTime Function() _clock;
  final VaultObjectCrypto _objectCrypto;
  final SecureKey _indexKey;
  final EntryObjectCodec _entryCodec = const EntryObjectCodec();
  final ManifestV1Codec _manifestCodec = const ManifestV1Codec();
  final VaultHeadCodec _headCodec = const VaultHeadCodec();

  String get manifestId => _manifestId;

  @override
  Future<Entry> createEntry(EntryDraft draft) async {
    final id = _uuidV4();
    final entry = Entry(
      id: EntryId(id),
      revision: 1,
      occurredAt: draft.occurredAt,
      body: draft.body,
      mood: draft.mood,
      tags: draft.tags,
      attachments: draft.attachments,
    );
    await _commit(entry.id, 1, draft, tombstone: false);
    return entry;
  }

  @override
  Future<Entry> updateEntry(
    EntryId id,
    int expectedRevision,
    EntryDraft draft,
  ) async {
    final current = _currentRevision(id);
    if (current != expectedRevision) {
      throw EntryRevisionConflict(id, expectedRevision, current);
    }
    final entry = Entry(
      id: id,
      revision: current + 1,
      occurredAt: draft.occurredAt,
      body: draft.body,
      mood: draft.mood,
      tags: draft.tags,
      attachments: draft.attachments,
    );
    await _commit(id, entry.revision, draft, tombstone: false);
    return entry;
  }

  @override
  Future<void> deleteEntry(EntryId id, int expectedRevision) async {
    final current = _currentRevision(id);
    if (current != expectedRevision) {
      throw EntryRevisionConflict(id, expectedRevision, current);
    }
    final draft = EntryDraft(
      occurredAt: _clock(),
      body: '',
      mood: null,
      tags: const [],
      attachments: const [],
    );
    await _commit(id, current + 1, draft, tombstone: true);
  }

  @override
  Future<List<Entry>> timeline() async {
    final rows = _index.database.select(
      "SELECT id FROM entries WHERE status = 'active' ORDER BY occurred_at DESC",
    );
    return [for (final row in rows) _loadEntry(row['id'] as String)];
  }

  @override
  Future<List<Entry>> searchEntries(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return timeline();
    final entries = await timeline();
    return [
      for (final entry in entries)
        if (entry.body.toLowerCase().contains(normalized)) entry,
    ];
  }

  @override
  Future<List<Tag>> listTags() async {
    final rows = _index.database.select(
      'SELECT id, name_ciphertext, color FROM tags ORDER BY name_ciphertext',
    );
    final cipher = SearchCipher(_sodium, _indexKey);
    final seen = <String>{};
    final tags = <Tag>[];
    for (final row in rows) {
      final id = row['id'] as String;
      if (!seen.add(id)) continue;
      final name = cipher.decrypt(row['name_ciphertext'] as Uint8List);
      tags.add(Tag(id: TagId(id), name: name, color: row['color'] as int));
    }
    return tags;
  }

  void dispose() {
    _indexKey.dispose();
  }

  /// Encrypts and persists an entry/tombstone object, advances the manifest
  /// and HEAD, then updates the index.
  Future<void> _commit(
    EntryId id,
    int revision,
    EntryDraft draft, {
    required bool tombstone,
  }) async {
    final plaintext = tombstone
        ? _entryCodec.encodeTombstone(
            id: id.value,
            revision: revision,
            deviceId: _deviceId,
            createdAt: _clock(),
          )
        : _entryCodec.encodeEntry(
            id: id.value,
            revision: revision,
            deviceId: _deviceId,
            createdAt: _clock(),
            draft: draft,
          );
    final type = tombstone ? VaultObjectType.tombstone : VaultObjectType.entry;
    final ciphertext = _objectCrypto.encrypt(
      plaintext: plaintext,
      masterKey: _masterKey,
      vaultUuid: _vaultUuid,
      type: type,
      schemaVersion: 1,
    );
    final objectId = objectIdFromCiphertext(ciphertext);
    await _persistObject(objectId, ciphertext);
    await _advanceManifest(id.value, objectId);
    _updateIndex(id.value, revision, draft, tombstone: tombstone);
  }

  int _currentRevision(EntryId id) {
    final heads = _manifest.entities[id.value];
    if (heads == null || heads.isEmpty) {
      throw EntryNotFound(id);
    }
    final record = _loadObject(heads.first);
    return record.revision;
  }

  Entry _loadEntry(String id) {
    final heads = _manifest.entities[id];
    if (heads == null || heads.isEmpty) {
      throw EntryNotFound(EntryId(id));
    }
    final record = _loadObject(heads.first);
    if (record is! EntryRecord) {
      throw EntryNotFound(EntryId(id));
    }
    return record.entry;
  }

  EntryObject _loadObject(String objectId) {
    final bytes = File(
      '${_vault.path}${Platform.pathSeparator}objects'
      '${Platform.pathSeparator}${objectId.substring(0, 2)}'
      '${Platform.pathSeparator}$objectId',
    ).readAsBytesSync();
    final plaintext = _objectCrypto.decrypt(
      envelopeBytes: bytes,
      masterKey: _masterKey,
      vaultUuid: _vaultUuid,
    );
    try {
      return _entryCodec.decode(plaintext);
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Future<void> _persistObject(String objectId, Uint8List ciphertext) async {
    final objects = Directory('${_vault.path}${Platform.pathSeparator}objects');
    final shard = Directory(
      '${objects.path}${Platform.pathSeparator}${objectId.substring(0, 2)}',
    );
    if (!await shard.exists()) {
      await shard.create();
      await _durability.syncDirectory(objects);
    }
    final writer = AtomicFileWriter(durability: _durability, random: _random);
    await writer.write(
      File('${shard.path}${Platform.pathSeparator}$objectId'),
      ciphertext,
    );
  }

  Future<void> _advanceManifest(String entityId, String objectId) async {
    final entities = Map<String, List<String>>.from(_manifest.entities);
    entities[entityId] = [objectId];
    final knownDevices = Map<String, DateTime>.from(_manifest.knownDevices)
      ..[_deviceId] = _clock();
    final next = _manifest.copyWith(
      entities: entities,
      parentIds: [_manifestId],
      writerDeviceId: _deviceId,
      createdAt: _clock(),
      knownDevices: knownDevices,
    );
    final plaintext = _manifestCodec.encode(next);
    final ciphertext = _objectCrypto.encrypt(
      plaintext: plaintext,
      masterKey: _masterKey,
      vaultUuid: _vaultUuid,
      type: VaultObjectType.manifest,
      schemaVersion: 1,
    );
    final identity = ManifestIdentity.fromCiphertext(ciphertext);
    final writer = AtomicFileWriter(durability: _durability, random: _random);
    final manifests = Directory(
      '${_vault.path}${Platform.pathSeparator}manifests',
    );
    await writer.write(
      File('${manifests.path}${Platform.pathSeparator}${identity.manifestId}'),
      ciphertext,
    );
    await writer.write(
      File('${_vault.path}${Platform.pathSeparator}HEAD'),
      _headCodec.encode(VaultHead(identity)),
    );
    _manifest = next;
    _manifestId = identity.manifestId;
  }

  void _updateIndex(
    String entryId,
    int revision,
    EntryDraft draft, {
    required bool tombstone,
  }) {
    final cipher = SearchCipher(_sodium, _indexKey);
    final occurredAt = formatTimestamp(draft.occurredAt);
    final updatedAt = formatTimestamp(_clock());
    final status = tombstone ? 'deleted' : 'active';
    final database = _index.database;
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute(
        'INSERT INTO entries '
        '(id, revision, occurred_at, updated_at, status, search_ciphertext) '
        'VALUES (?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET revision = excluded.revision, '
        'occurred_at = excluded.occurred_at, updated_at = excluded.updated_at, '
        'status = excluded.status, '
        'search_ciphertext = excluded.search_ciphertext',
        [
          entryId,
          revision,
          occurredAt,
          updatedAt,
          status,
          cipher.encrypt(tombstone ? '' : draft.body),
        ],
      );

      database.execute('DELETE FROM entry_tags WHERE entry_id = ?', [entryId]);
      database.execute('DELETE FROM attachments WHERE entry_id = ?', [entryId]);

      for (final tag in draft.tags) {
        database.execute(
          'INSERT INTO tags (id, name_ciphertext, normalized_name_ciphertext, '
          'color) VALUES (?, ?, ?, ?) '
          'ON CONFLICT(id) DO UPDATE SET name_ciphertext = '
          'excluded.name_ciphertext, '
          'normalized_name_ciphertext = excluded.normalized_name_ciphertext, '
          'color = excluded.color',
          [
            tag.id.value,
            cipher.encrypt(tag.name),
            cipher.encrypt(normalizeTagName(tag.name)),
            tag.color,
          ],
        );
        database.execute(
          'INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)',
          [entryId, tag.id.value],
        );
      }

      for (final attachment in draft.attachments) {
        database.execute(
          'INSERT OR REPLACE INTO attachments (id, entry_id, blob_id) '
          'VALUES (?, ?, ?)',
          [attachment.id.value, entryId, attachment.blobId.value],
        );
      }

      database.execute('COMMIT');
    } catch (_) {
      if (!database.autocommit) database.execute('ROLLBACK');
      rethrow;
    }
  }

  String _uuidV4() {
    final bytes = _sodium.randombytes.buf(16);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
