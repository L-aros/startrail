import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';

abstract interface class VaultBackend {
  Future<String?> create(String path, Int8List passwordBytes);
  Future<String?> unlock(String path, Int8List passwordBytes);
  Future<void> lock();
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
      _request('create', path, passwordBytes);

  @override
  Future<String?> unlock(String path, Int8List passwordBytes) =>
      _request('unlock', path, passwordBytes);

  Future<String?> _request(
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
  UnlockedVault? session;
  await for (final message in commands.cast<Map<Object?, Object?>>()) {
    final operation = message['operation'] as String;
    final reply = message['reply'] as SendPort;
    if (operation == 'lock') {
      session?.dispose();
      session = null;
      reply.send(const {'ok': true});
      commands.close();
      break;
    }

    Int8List? password;
    try {
      session?.dispose();
      session = null;
      final bytes = (message['password'] as TransferableTypedData)
          .materialize()
          .asUint8List();
      password = Int8List.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      final path = message['path'] as String;
      if (operation == 'create') {
        final creator = await VaultCreator.initialize(
          durability: createDirectoryDurability(),
        );
        await creator.create(target: Directory(path), passwordBytes: password);
      }
      final unlocker = await VaultUnlocker.initialize();
      session = await unlocker.unlock(
        vault: Directory(path),
        passwordBytes: password,
      );
      reply.send(const {'ok': true});
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
  session?.dispose();
  Isolate.exit();
}
