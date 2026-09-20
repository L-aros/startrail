import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:infrastructure/infrastructure.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

void main() {
  late SodiumSumo sodium;
  late Directory sandbox;
  late SecureKey masterKey;

  setUp(() async {
    sodium = await SodiumSumoInit.init();
    sandbox = Directory.systemTemp.createTempSync('startrail-index-test-');
    masterKey = sodium.secureCopy(
      Uint8List.fromList(List<int>.generate(32, (index) => index)),
    );
  });

  tearDown(() {
    masterKey.dispose();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('index KDF matches the independent libsodium vector', () {
    final derived = IndexKeyDeriver(sodium).derive(masterKey);
    addTearDown(derived.dispose);

    expect(
      derived.runUnlockedSync(_hex),
      '375be8ce31b03032ab403c28e2bb8666'
      '11d5d0197acec6d103714a93da1b731d',
    );
  });

  test('creates and validates schema v1 with manifest generation', () async {
    final path = '${sandbox.path}/index.db';
    final generation = 'a' * 52;
    final factory = IndexDatabaseFactory(
      sodium,
      durability: PosixDirectoryDurability(),
    );

    final index = await factory.create(
      path,
      masterKey: masterKey,
      manifestId: generation,
    );
    addTearDown(index.close);

    expect(index.database.userVersion, 1);
    expect(
      index.database.select('PRAGMA application_id').single.values.single,
      0x53544958,
    );
    expect(
      index.database
          .select('SELECT manifest_id FROM index_meta')
          .single
          .values
          .single,
      generation,
    );
    expect(
      index.database
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
          )
          .map((row) => row['name']),
      containsAll(<String>{
        'attachments',
        'conflicts',
        'entries',
        'entry_tags',
        'index_meta',
        'outbox',
        'sync_state',
        'tags',
      }),
    );
    expect(
      () => index.database.execute(
        "INSERT INTO entries VALUES ('id', -1, 't', 't', 'active', X'00')",
      ),
      throwsA(anything),
    );
  });

  test(
    'reopens only with matching authenticated manifest generation',
    () async {
      final path = '${sandbox.path}/index.db';
      final factory = IndexDatabaseFactory(
        sodium,
        durability: PosixDirectoryDurability(),
      );
      final created = await factory.create(
        path,
        masterKey: masterKey,
        manifestId: 'b' * 52,
      );
      created.close();

      final reopened = factory.open(
        path,
        masterKey: masterKey,
        manifestId: 'b' * 52,
      );
      reopened.close();

      expect(
        () => factory.open(path, masterKey: masterKey, manifestId: 'c' * 52),
        throwsA(isA<IndexGenerationMismatch>()),
      );
    },
  );

  test('open failure quarantines the database group and rebuilds', () async {
    final local = Directory('${sandbox.path}/local')..createSync();
    final path = '${local.path}/index.db';
    final factory = IndexDatabaseFactory(
      sodium,
      durability: PosixDirectoryDurability(),
      random: _ZeroRandom(),
      clock: () => DateTime.utc(2026, 9, 20, 8, 30),
    );
    final created = await factory.create(
      path,
      masterKey: masterKey,
      manifestId: 'd' * 52,
    );
    created.close();
    File(path).writeAsBytesSync([9, 10, 11], flush: true);
    File('$path-wal').writeAsBytesSync([1, 2, 3]);
    File('$path-shm').writeAsBytesSync([4, 5, 6]);

    final rebuilt = await factory.openOrRebuild(
      path,
      masterKey: masterKey,
      manifestId: 'e' * 52,
      populate: (database) {
        database.execute('INSERT INTO entries VALUES (?, ?, ?, ?, ?, ?)', [
          'entry',
          1,
          '2026-09-20T08:30:00Z',
          '2026-09-20T08:30:00Z',
          'active',
          [7, 8],
        ]);
      },
    );
    addTearDown(rebuilt.close);

    expect(
      rebuilt.database.select('SELECT id FROM entries').single['id'],
      'entry',
    );
    final quarantined = Directory(
      '${local.path}/quarantine',
    ).listSync().whereType<Directory>().single;
    expect(File('${quarantined.path}/index.db').existsSync(), isTrue);
    expect(File('${quarantined.path}/index.db-wal').readAsBytesSync(), [
      1,
      2,
      3,
    ]);
    expect(File('${quarantined.path}/index.db-shm').existsSync(), isTrue);
  });

  test('failed rebuild preserves quarantine and publishes nothing', () async {
    final local = Directory('${sandbox.path}/local')..createSync();
    final path = '${local.path}/index.db';
    final factory = IndexDatabaseFactory(
      sodium,
      durability: PosixDirectoryDurability(),
      random: _ZeroRandom(),
      clock: () => DateTime.utc(2026, 9, 20, 9),
    );
    final created = await factory.create(
      path,
      masterKey: masterKey,
      manifestId: 'f' * 52,
    );
    created.close();

    await expectLater(
      factory.openOrRebuild(
        path,
        masterKey: masterKey,
        manifestId: 'g' * 52,
        populate: (_) => throw StateError('injected rebuild failure'),
      ),
      throwsStateError,
    );

    expect(File(path).existsSync(), isFalse);
    expect(
      Directory('${local.path}/quarantine')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('index.db')),
      hasLength(1),
    );
    expect(
      local.listSync().whereType<File>().where(
        (file) => file.path.contains('.creating-'),
      ),
      isEmpty,
    );
  });
}

String _hex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}
