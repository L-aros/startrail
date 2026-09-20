import 'dart:io';
import 'dart:math';

import 'package:sodium/sodium_sumo.dart';
import 'package:sqlite3/sqlite3.dart';

import 'atomic_file_writer.dart';
import 'sqlcipher_raw_key_adapter.dart';

const indexSchemaVersion = 1;
const indexApplicationId = 0x53544958;
const indexKdfContext = 'STIDX001';
const indexKdfSubkeyId = 1;
const indexKeyBytes = 32;

final class IndexGenerationMismatch implements Exception {
  const IndexGenerationMismatch();

  @override
  String toString() => 'IndexGenerationMismatch';
}

final class IndexKeyDeriver {
  const IndexKeyDeriver(this._sodium);

  final SodiumSumo _sodium;

  SecureKey derive(SecureKey masterKey) => _sodium.crypto.kdf.deriveFromKey(
    masterKey: masterKey,
    context: indexKdfContext,
    subkeyId: BigInt.from(indexKdfSubkeyId),
    subkeyLen: indexKeyBytes,
  );
}

final class EncryptedIndexDatabase {
  EncryptedIndexDatabase(this.database, this._indexKey);

  final Database database;
  final SecureKey _indexKey;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      database.close();
    } finally {
      _indexKey.dispose();
    }
  }
}

final class IndexDatabaseFactory {
  IndexDatabaseFactory(
    SodiumSumo sodium, {
    required DirectoryDurability durability,
    SqlCipherRawKeyAdapter rawKeyAdapter = const SqlCipherRawKeyAdapter(),
    Random? random,
  }) : _keyDeriver = IndexKeyDeriver(sodium),
       _durability = durability,
       _rawKeyAdapter = rawKeyAdapter,
       _random = random ?? Random.secure();

  final IndexKeyDeriver _keyDeriver;
  final DirectoryDurability _durability;
  final SqlCipherRawKeyAdapter _rawKeyAdapter;
  final Random _random;

  Future<EncryptedIndexDatabase> create(
    String path, {
    required SecureKey masterKey,
    required String manifestId,
  }) async {
    _validateManifestId(manifestId);
    final target = File(path);
    if (await target.exists()) {
      throw FileSystemException('Index already exists');
    }
    if (!await target.parent.exists()) {
      throw FileSystemException('Index parent does not exist');
    }

    final temporary = File('$path.creating-${_randomSuffix()}');
    EncryptedIndexDatabase? created;
    try {
      created = _openConnection(temporary.path, masterKey);
      _configureConnection(created.database);
      _createSchema(created.database, manifestId);
      created.close();
      created = null;

      final handle = await temporary.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      await _durability.syncDirectory(target.parent);
      await temporary.rename(path);
      await _durability.syncDirectory(target.parent);
      return open(path, masterKey: masterKey, manifestId: manifestId);
    } catch (_) {
      created?.close();
      await _deleteDatabaseGroup(temporary.path);
      rethrow;
    }
  }

  EncryptedIndexDatabase open(
    String path, {
    required SecureKey masterKey,
    required String manifestId,
  }) {
    _validateManifestId(manifestId);
    final opened = _openConnection(path, masterKey);
    try {
      _configureConnection(opened.database);
      _validateIntegrity(opened.database);
      if (opened.database.userVersion != indexSchemaVersion ||
          _pragmaInt(opened.database, 'application_id') != indexApplicationId) {
        throw const FormatException('Unsupported index schema');
      }
      final rows = opened.database.select(
        'SELECT manifest_id FROM index_meta WHERE singleton = 1',
      );
      if (rows.length != 1 || rows.single['manifest_id'] != manifestId) {
        throw const IndexGenerationMismatch();
      }
      return opened;
    } catch (_) {
      opened.close();
      rethrow;
    }
  }

  EncryptedIndexDatabase _openConnection(String path, SecureKey masterKey) {
    final indexKey = _keyDeriver.derive(masterKey);
    try {
      final database = indexKey.runUnlockedSync(
        (bytes) => _rawKeyAdapter.open(path, rawKey: bytes),
      );
      return EncryptedIndexDatabase(database, indexKey);
    } catch (_) {
      indexKey.dispose();
      rethrow;
    }
  }

  void _configureConnection(Database database) {
    database
      ..execute('PRAGMA foreign_keys = ON')
      ..execute('PRAGMA trusted_schema = OFF')
      ..execute('PRAGMA secure_delete = ON')
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA synchronous = FULL');
  }

  void _createSchema(Database database, String manifestId) {
    database.execute('BEGIN IMMEDIATE');
    try {
      database
        ..execute('PRAGMA application_id = $indexApplicationId')
        ..execute('PRAGMA user_version = $indexSchemaVersion')
        ..execute(_schemaSql)
        ..execute(
          'INSERT INTO index_meta '
          '(singleton, schema_version, manifest_id) VALUES (1, 1, ?)',
          [manifestId],
        )
        ..execute('COMMIT');
    } catch (_) {
      if (!database.autocommit) database.execute('ROLLBACK');
      rethrow;
    }
  }

  void _validateIntegrity(Database database) {
    final cipher = database.select('PRAGMA cipher_integrity_check');
    if (cipher.isNotEmpty &&
        cipher.any(
          (row) => row.values.single.toString().toLowerCase() != 'ok',
        )) {
      throw const FormatException('Index integrity check failed');
    }
    final quick = database.select('PRAGMA quick_check(1)');
    if (quick.length != 1 ||
        quick.single.values.single.toString().toLowerCase() != 'ok') {
      throw const FormatException('Index integrity check failed');
    }
  }

  int _pragmaInt(Database database, String name) =>
      database.select('PRAGMA $name').single.values.single as int;

  void _validateManifestId(String manifestId) {
    if (!RegExp(r'^[a-z2-7]{52}$').hasMatch(manifestId)) {
      throw const FormatException('Invalid manifest id');
    }
  }

  Future<void> _deleteDatabaseGroup(String path) async {
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  String _randomSuffix() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

const _schemaSql = '''
CREATE TABLE index_meta (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  manifest_id TEXT NOT NULL CHECK (length(manifest_id) = 52)
) STRICT;
CREATE TABLE entries (
  id TEXT PRIMARY KEY,
  revision INTEGER NOT NULL CHECK (revision >= 0),
  occurred_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'deleted')),
  search_ciphertext BLOB NOT NULL
) STRICT;
CREATE TABLE tags (
  id TEXT PRIMARY KEY,
  name_ciphertext BLOB NOT NULL,
  normalized_name_ciphertext BLOB NOT NULL UNIQUE,
  color INTEGER NOT NULL CHECK (color BETWEEN 0 AND 4294967295)
) STRICT;
CREATE TABLE entry_tags (
  entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (entry_id, tag_id)
) STRICT, WITHOUT ROWID;
CREATE TABLE attachments (
  id TEXT PRIMARY KEY,
  entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  blob_id TEXT NOT NULL CHECK (length(blob_id) = 52)
) STRICT;
CREATE TABLE sync_state (
  remote_id TEXT PRIMARY KEY,
  head_id TEXT,
  cursor TEXT,
  last_success_at TEXT
) STRICT;
CREATE TABLE conflicts (
  id TEXT PRIMARY KEY,
  entity_id TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('unresolved', 'resolved'))
) STRICT;
CREATE TABLE outbox (
  object_id TEXT PRIMARY KEY CHECK (length(object_id) = 52),
  priority INTEGER NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0)
) STRICT;
CREATE INDEX entries_updated_at ON entries(updated_at);
CREATE INDEX entries_occurred_at ON entries(occurred_at);
CREATE INDEX attachments_entry_id ON attachments(entry_id);
CREATE INDEX conflicts_entity_state ON conflicts(entity_id, state);
CREATE INDEX outbox_priority_attempts ON outbox(priority DESC, attempts ASC);
''';
