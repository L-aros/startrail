import 'dart:io';
import 'dart:typed_data';

import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('startrail-create-');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('publishes a self-consistent initial vault transaction', () async {
    final target = Directory('${sandbox.path}${Platform.pathSeparator}vault');
    final creator = await VaultCreator.initialize(
      durability: createDirectoryDurability(),
      clock: () => DateTime.utc(2026, 9, 20, 1, 2, 3, 4),
    );

    final created = await creator.create(
      target: target,
      passwordBytes: Int8List.fromList('test password'.codeUnits),
    );

    expect(
      await File(
        '${target.path}${Platform.pathSeparator}vault.header',
      ).exists(),
      isTrue,
    );
    expect(
      await File('${target.path}${Platform.pathSeparator}HEAD').exists(),
      isTrue,
    );
    expect(
      await Directory(
        '${target.path}${Platform.pathSeparator}objects',
      ).exists(),
      isTrue,
    );
    expect(
      await Directory('${target.path}${Platform.pathSeparator}local').exists(),
      isTrue,
    );
    final head = const VaultHeadCodec().decode(
      await File('${target.path}${Platform.pathSeparator}HEAD').readAsBytes(),
    );
    final manifest = File(
      '${target.path}${Platform.pathSeparator}manifests'
      '${Platform.pathSeparator}${head.manifest.manifestId}',
    );
    expect(await manifest.exists(), isTrue);
    const VaultHeadCodec().verifyManifest(head, await manifest.readAsBytes());
    expect(created.vaultUuid, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  for (final stage in VaultCreationStage.values) {
    test(
      'does not publish a vault when interrupted after ${stage.name}',
      () async {
        final target = Directory(
          '${sandbox.path}${Platform.pathSeparator}vault',
        );
        final creator = await VaultCreator.initialize(
          durability: createDirectoryDurability(),
          faultInjector: (current) async {
            if (current == stage) throw StateError('injected ${stage.name}');
          },
        );

        await expectLater(
          creator.create(target: target, passwordBytes: Int8List.fromList([1])),
          throwsStateError,
        );

        expect(await target.exists(), isFalse);
        final leftovers = await sandbox.list().toList();
        expect(leftovers, isEmpty);
      },
    );
  }
}
