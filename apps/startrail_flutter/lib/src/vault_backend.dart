import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';

/// Unified result returned by entry operations, carrying either an error code
/// or decoded data (entry map / entry list / tag list) across the isolate.
final class BackendResult {
  const BackendResult._(this.error, this.data);

  final String? error;
  final Object? data;

  bool get ok => error == null;

  factory BackendResult.ok([Object? data]) => BackendResult._(null, data);

  factory BackendResult.fail(String error) => BackendResult._(error, null);
}

abstract interface class VaultBackend {
  Future<String?> create(String path, Int8List passwordBytes);
  Future<String?> unlock(String path, Int8List passwordBytes);
  Future<void> lock();

  Future<BackendResult> createEntry(Map<String, Object?> draft);
  Future<BackendResult> updateEntry(
    String id,
    int revision,
    Map<String, Object?> draft,
  );
  Future<BackendResult> deleteEntry(String id, int revision);
  Future<BackendResult> timeline();
  Future<BackendResult> search(String query);
  Future<BackendResult> tags();
  Future<BackendResult> importAttachment(String path, String mime);
}

final class IsolateVaultBackend implements VaultBackend {
  Isolate? _isolate;
  SendPort? _commands;

  Future<SendPort> _ensureWorker() async {
    final existing = _commands;
    if (existing != null) return existing;
    final ready = ReceivePort();
    _isolate = await Isolate.spawn(_vaultWorker, ready.sendPort);
    final port = await ready.first as SendPort;
    ready.close();
    _commands = port;
    return port;
  }

  @override
  Future<String?> create(String path, Int8List passwordBytes) =>
      _authRequest('create', path, passwordBytes);

  @override
  Future<String?> unlock(String path, Int8List passwordBytes) =>
      _authRequest('unlock', path, passwordBytes);

  @override
  Future<BackendResult> createEntry(Map<String, Object?> draft) =>
      _entryRequest({'operation': 'entry.create', 'draft': draft});

  @override
  Future<BackendResult> updateEntry(
    String id,
    int revision,
    Map<String, Object?> draft,
  ) => _entryRequest({
    'operation': 'entry.update',
    'id': id,
    'revision': revision,
    'draft': draft,
  });

  @override
  Future<BackendResult> deleteEntry(String id, int revision) => _entryRequest({
    'operation': 'entry.delete',
    'id': id,
    'revision': revision,
  });

  @override
  Future<BackendResult> timeline() =>
      _entryRequest(const {'operation': 'entry.timeline'});

  @override
  Future<BackendResult> search(String query) =>
      _entryRequest({'operation': 'entry.search', 'query': query});

  @override
  Future<BackendResult> tags() =>
      _entryRequest(const {'operation': 'entry.tags'});

  @override
  Future<BackendResult> importAttachment(String path, String mime) =>
      _entryRequest({
        'operation': 'attachment.import',
        'path': path,
        'mime': mime,
      });

  Future<String?> _authRequest(
    String operation,
    String path,
    Int8List passwordBytes,
  ) async {
    final worker = await _ensureWorker();
    final response = ReceivePort();
    final transferable = TransferableTypedData.fromList([
      Uint8List.view(
        passwordBytes.buffer,
        passwordBytes.offsetInBytes,
        passwordBytes.lengthInBytes,
      ),
    ]);
    worker.send({
      'operation': operation,
      'path': path,
      'password': transferable,
      'reply': response.sendPort,
    });
    final result = await response.first as Map<Object?, Object?>;
    response.close();
    return result['error'] as String?;
  }

  Future<BackendResult> _entryRequest(Map<String, Object?> message) async {
    final worker = await _ensureWorker();
    final response = ReceivePort();
    worker.send({...message, 'reply': response.sendPort});
    final result = await response.first as Map<Object?, Object?>;
    response.close();
    final error = result['error'];
    if (error != null) return BackendResult.fail(error as String);
    return BackendResult.ok(result['data']);
  }

  @override
  Future<void> lock() async {
    final worker = _commands;
    if (worker != null) {
      final response = ReceivePort();
      worker.send({'operation': 'lock', 'reply': response.sendPort});
      await response.first;
      response.close();
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
  }
}

Future<void> _vaultWorker(SendPort ready) async {
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  VaultSession? vault;
  await for (final message in commands.cast<Map<Object?, Object?>>()) {
    final operation = message['operation'] as String;
    final reply = message['reply'] as SendPort;
    if (operation == 'lock') {
      vault?.dispose();
      vault = null;
      reply.send(const {'ok': true});
      commands.close();
      break;
    }

    Int8List? password;
    try {
      if (operation == 'create') {
        vault?.dispose();
        vault = null;
        final bytes = (message['password'] as TransferableTypedData)
            .materialize()
            .asUint8List();
        password = Int8List.view(
          bytes.buffer,
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
        final path = message['path'] as String;
        final creator = await VaultCreator.initialize(
          durability: createDirectoryDurability(),
        );
        await creator.create(target: Directory(path), passwordBytes: password);
        vault = await VaultSession.open(
          vault: Directory(path),
          passwordBytes: password,
          durability: createDirectoryDurability(),
        );
        reply.send(const {'ok': true});
        continue;
      }
      if (operation == 'unlock') {
        vault?.dispose();
        vault = null;
        final bytes = (message['password'] as TransferableTypedData)
            .materialize()
            .asUint8List();
        password = Int8List.view(
          bytes.buffer,
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
        final path = message['path'] as String;
        vault = await VaultSession.open(
          vault: Directory(path),
          passwordBytes: password,
          durability: createDirectoryDurability(),
        );
        reply.send(const {'ok': true});
        continue;
      }

      final session = vault;
      if (session == null) {
        reply.send(const {'error': 'VAULT_LOCKED'});
        continue;
      }
      final service = EntryService(session.entryStore);
      switch (operation) {
        case 'entry.create':
          final entry = await service.createEntry(
            _draftFromJson(_asMap(message['draft'])),
          );
          reply.send({'ok': true, 'data': _entryToJson(entry)});
        case 'entry.update':
          final entry = await service.updateEntry(
            EntryId(message['id'] as String),
            message['revision'] as int,
            _draftFromJson(_asMap(message['draft'])),
          );
          reply.send({'ok': true, 'data': _entryToJson(entry)});
        case 'entry.delete':
          await service.deleteEntry(
            EntryId(message['id'] as String),
            message['revision'] as int,
          );
          reply.send(const {'ok': true});
        case 'entry.timeline':
          final entries = await service.timeline();
          reply.send({
            'ok': true,
            'data': [for (final entry in entries) _entryToJson(entry)],
          });
        case 'entry.search':
          final entries = await service.search(message['query'] as String);
          reply.send({
            'ok': true,
            'data': [for (final entry in entries) _entryToJson(entry)],
          });
        case 'entry.tags':
          final tags = await service.tags();
          reply.send({
            'ok': true,
            'data': [
              for (final tag in tags)
                {'id': tag.id.value, 'name': tag.name, 'color': tag.color},
            ],
          });
        case 'attachment.import':
          final path = message['path'] as String;
          final mime =
              (message['mime'] as String?) ?? 'application/octet-stream';
          final bytes = await File(path).readAsBytes();
          final attachment = await session.entryStore.importBlob(
            mime: mime,
            bytes: bytes,
          );
          reply.send({
            'ok': true,
            'data': {
              'id': attachment.id.value,
              'blob_id': attachment.blobId.value,
              'mime': attachment.mime,
              'byte_size': attachment.byteSize,
              'digest': attachment.digest,
            },
          });
        default:
          reply.send(const {'error': 'VAULT_OPERATION_FAILED'});
      }
    } on EntryError catch (error) {
      reply.send({'error': error.code});
    } on VaultFailure catch (error) {
      reply.send({'error': error.code});
    } on FileSystemException {
      reply.send(const {'error': 'VAULT_IO_FAILED'});
    } on FormatException {
      reply.send(const {'error': 'VAULT_FORMAT_UNSUPPORTED'});
    } catch (_) {
      reply.send(const {'error': 'VAULT_OPERATION_FAILED'});
    } finally {
      password?.fillRange(0, password.length, 0);
    }
  }
  vault?.dispose();
  Isolate.exit();
}

Map<String, Object?> _asMap(Object? value) =>
    (value as Map).cast<String, Object?>();

EntryDraft _draftFromJson(Map<String, Object?> json) => EntryDraft(
  occurredAt: DateTime.parse(json['occurred_at'] as String),
  body: json['body'] as String,
  mood: json['mood'] as String?,
  tags: [
    for (final raw in json['tags'] as List)
      Tag(
        id: TagId((raw as Map)['id'] as String),
        name: raw['name'] as String,
        color: raw['color'] as int,
      ),
  ],
  attachments: [
    for (final raw in json['attachments'] as List)
      Attachment(
        id: AttachmentId((raw as Map)['id'] as String),
        blobId: BlobId(raw['blob_id'] as String),
        mime: raw['mime'] as String,
        byteSize: raw['byte_size'] as int,
        digest: raw['digest'] as String,
      ),
  ],
);

Map<String, Object?> _entryToJson(Entry entry) => {
  'id': entry.id.value,
  'revision': entry.revision,
  'occurred_at': entry.occurredAt.toUtc().toIso8601String(),
  'body': entry.body,
  'mood': entry.mood,
  'tags': [
    for (final tag in entry.tags)
      {'id': tag.id.value, 'name': tag.name, 'color': tag.color},
  ],
  'attachments': [
    for (final attachment in entry.attachments)
      {
        'id': attachment.id.value,
        'blob_id': attachment.blobId.value,
        'mime': attachment.mime,
        'byte_size': attachment.byteSize,
        'digest': attachment.digest,
      },
  ],
};
