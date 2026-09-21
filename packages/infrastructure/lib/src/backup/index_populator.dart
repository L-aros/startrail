import 'dart:io';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:sqlite3/sqlite3.dart';

import '../crypto/vault_object_crypto.dart';
import '../format/entry_object.dart';
import '../format/manifest_codec.dart';
import '../storage/index_database.dart';
import '../storage/search_cipher.dart';

/// Rebuilds the derived SQLCipher index (`entries`/`tags`/`entry_tags`/
/// `attachments`) from the authenticated objects and the current manifest.
///
/// This closes the Milestone 3 `populate` gap: after a crash-induced index
/// rebuild, a quarantine, or a restore, the index is reconstructed solely from
/// the authoritative encrypted objects (ADR-0011 generation isolation plus the
/// ADR-0016 "index is always rebuildable" invariant). Multi-head conflicts are
/// deferred to the sync milestone; the first head mirrors the online store.
final class IndexPopulator {
  IndexPopulator({
    required SodiumSumo sodium,
    required Uint8List vaultUuid,
    required SecureKey masterKey,
    required ManifestV1 manifest,
    required Directory vault,
  }) : _sodium = sodium,
       _vaultUuid = Uint8List.fromList(vaultUuid),
       _masterKey = masterKey,
       _manifest = manifest,
       _vault = vault {
    if (vaultUuid.length != 16) {
      throw ArgumentError.value(vaultUuid.length, 'vaultUuid.length');
    }
  }

  final SodiumSumo _sodium;
  final Uint8List _vaultUuid;
  final SecureKey _masterKey;
  final ManifestV1 _manifest;
  final Directory _vault;
  final EntryObjectCodec _entryCodec = const EntryObjectCodec();

  Future<void> populate(Database database) async {
    final objectCrypto = VaultObjectCrypto(_sodium);
    final indexKey = IndexKeyDeriver(_sodium).derive(_masterKey);
    try {
      final cipher = SearchCipher(_sodium, indexKey);
      final separator = Platform.pathSeparator;
      for (final entity in _manifest.entities.entries) {
        final entryId = entity.key;
        final heads = entity.value;
        if (heads.isEmpty) continue;
        final record = _loadObject(objectCrypto, heads.first, separator);
        if (record is TombstoneRecord) {
          _insertEntry(
            database,
            cipher,
            entryId: entryId,
            revision: record.revision,
            body: '',
            occurredAt: record.createdAt,
            updatedAt: record.createdAt,
            tags: const [],
            attachments: const [],
            status: 'deleted',
          );
        } else if (record is EntryRecord) {
          final entry = record.entry;
          _insertEntry(
            database,
            cipher,
            entryId: entryId,
            revision: entry.revision,
            body: entry.body,
            occurredAt: entry.occurredAt,
            updatedAt: record.createdAt,
            tags: entry.tags,
            attachments: entry.attachments,
            status: 'active',
          );
        }
      }
    } finally {
      indexKey.dispose();
    }
  }

  EntryObject _loadObject(
    VaultObjectCrypto objectCrypto,
    String objectId,
    String separator,
  ) {
    final bytes = File(
      '${_vault.path}$separator'
      'objects$separator${objectId.substring(0, 2)}$separator$objectId',
    ).readAsBytesSync();
    final plaintext = objectCrypto.decrypt(
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

  void _insertEntry(
    Database database,
    SearchCipher cipher, {
    required String entryId,
    required int revision,
    required String body,
    required DateTime occurredAt,
    required DateTime updatedAt,
    required List<Tag> tags,
    required List<Attachment> attachments,
    required String status,
  }) {
    database.execute(
      'INSERT INTO entries '
      '(id, revision, occurred_at, updated_at, status, search_ciphertext) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        entryId,
        revision,
        formatTimestamp(occurredAt),
        formatTimestamp(updatedAt),
        status,
        cipher.encrypt(body),
      ],
    );
    for (final tag in tags) {
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
    for (final attachment in attachments) {
      database.execute(
        'INSERT OR REPLACE INTO attachments (id, entry_id, blob_id) '
        'VALUES (?, ?, ?)',
        [attachment.id.value, entryId, attachment.blobId.value],
      );
    }
  }
}
