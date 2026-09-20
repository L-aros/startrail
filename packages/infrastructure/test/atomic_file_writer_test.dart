import 'dart:io';
import 'dart:typed_data';

import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('startrail-atomic-test-');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('installs new bytes and synchronizes directory mutations', () async {
    final durability = _RecordingDurability();
    final target = File('${sandbox.path}${Platform.pathSeparator}HEAD');
    final writer = AtomicFileWriter(durability: durability);

    await writer.write(target, Uint8List.fromList([1, 2, 3]));

    expect(await target.readAsBytes(), [1, 2, 3]);
    expect(durability.syncedDirectories, hasLength(2));
    expect(await _artifacts(target), isEmpty);
  });

  for (final stage in AtomicWriteStage.values) {
    test('restores prior bytes when interrupted after ${stage.name}', () async {
      final target = File('${sandbox.path}${Platform.pathSeparator}HEAD');
      await target.writeAsBytes([9, 8, 7], flush: true);
      final writer = AtomicFileWriter(
        durability: _RecordingDurability(),
        faultInjector: (current) async {
          if (current == stage) throw StateError('injected ${stage.name}');
        },
      );

      await expectLater(
        writer.write(target, Uint8List.fromList([1, 2, 3])),
        throwsStateError,
      );

      expect(await target.readAsBytes(), [9, 8, 7]);
      expect(await _artifacts(target), isEmpty);
    });
  }

  test(
    'removes an uncommitted first write after replacement failure',
    () async {
      final target = File(
        '${sandbox.path}${Platform.pathSeparator}vault.header',
      );
      final writer = AtomicFileWriter(
        durability: _RecordingDurability(),
        faultInjector: (stage) async {
          if (stage == AtomicWriteStage.replacementInstalled) {
            throw StateError('injected');
          }
        },
      );

      await expectLater(
        writer.write(target, Uint8List.fromList([1])),
        throwsStateError,
      );

      expect(await target.exists(), isFalse);
      expect(await _artifacts(target), isEmpty);
    },
  );

  test('refuses to overwrite an unresolved rollback path', () async {
    final target = File('${sandbox.path}${Platform.pathSeparator}HEAD');
    await File('${target.path}.rollback').writeAsBytes([4], flush: true);
    final writer = AtomicFileWriter(durability: _RecordingDurability());

    await expectLater(
      writer.write(target, Uint8List.fromList([1])),
      throwsA(isA<FileSystemException>()),
    );
  });
}

Future<List<FileSystemEntity>> _artifacts(File target) =>
    target.parent.list().where((entity) => entity.path != target.path).toList();

final class _RecordingDurability implements DirectoryDurability {
  final List<String> syncedDirectories = [];

  @override
  Future<void> syncDirectory(Directory directory) async {
    syncedDirectories.add(directory.path);
  }
}
