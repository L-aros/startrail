import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Platform boundary for persisting directory-entry changes after rename/delete.
abstract interface class DirectoryDurability {
  Future<void> syncDirectory(Directory directory);
}

enum AtomicWriteStage {
  temporaryFileSynced,
  previousFileMovedToRollback,
  replacementInstalled,
}

typedef AtomicWriteFaultInjector =
    Future<void> Function(AtomicWriteStage stage);

final class AtomicFileWriter {
  AtomicFileWriter({
    required DirectoryDurability durability,
    AtomicWriteFaultInjector? faultInjector,
    Random? random,
  }) : _durability = durability,
       _faultInjector = faultInjector,
       _random = random ?? Random.secure();

  final DirectoryDurability _durability;
  final AtomicWriteFaultInjector? _faultInjector;
  final Random _random;

  Future<void> write(File target, Uint8List bytes) async {
    final parent = target.parent;
    if (!await parent.exists()) {
      throw FileSystemException('Target directory does not exist', parent.path);
    }
    final rollback = File('${target.path}.rollback');
    if (await rollback.exists()) {
      throw FileSystemException(
        'Unresolved rollback file requires recovery',
        rollback.path,
      );
    }
    final temporary = File('${target.path}.tmp-${_randomSuffix()}');
    final hadPrevious = await target.exists();
    var previousMoved = false;
    var replacementInstalled = false;

    try {
      await temporary.create(exclusive: true);
      final handle = await temporary.open(mode: FileMode.write);
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
      await _durability.syncDirectory(parent);
      await _inject(AtomicWriteStage.temporaryFileSynced);

      if (hadPrevious) {
        await target.rename(rollback.path);
        previousMoved = true;
        await _durability.syncDirectory(parent);
        await _inject(AtomicWriteStage.previousFileMovedToRollback);
      }

      await temporary.rename(target.path);
      replacementInstalled = true;
      await _durability.syncDirectory(parent);
      await _inject(AtomicWriteStage.replacementInstalled);

      if (previousMoved) {
        await rollback.delete();
        await _durability.syncDirectory(parent);
      }
    } catch (_) {
      await _rollback(
        target: target,
        temporary: temporary,
        rollback: rollback,
        parent: parent,
        hadPrevious: hadPrevious,
        previousMoved: previousMoved,
        replacementInstalled: replacementInstalled,
      );
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _rollback({
    required File target,
    required File temporary,
    required File rollback,
    required Directory parent,
    required bool hadPrevious,
    required bool previousMoved,
    required bool replacementInstalled,
  }) async {
    if (replacementInstalled && await target.exists()) {
      await target.delete();
      await _durability.syncDirectory(parent);
    }
    if (previousMoved && await rollback.exists()) {
      await rollback.rename(target.path);
      await _durability.syncDirectory(parent);
    } else if (!hadPrevious && await target.exists()) {
      await target.delete();
      await _durability.syncDirectory(parent);
    }
    if (await temporary.exists()) await temporary.delete();
  }

  Future<void> _inject(AtomicWriteStage stage) async {
    final injector = _faultInjector;
    if (injector != null) await injector(stage);
  }

  String _randomSuffix() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
