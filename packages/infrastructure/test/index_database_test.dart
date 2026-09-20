import 'dart:io';
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
}

String _hex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
