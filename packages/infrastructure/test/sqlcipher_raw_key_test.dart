import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:infrastructure/infrastructure.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late SqlCipherRawKeyAdapter adapter;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'startrail-sqlcipher-test-',
    );
    databasePath = '${temporaryDirectory.path}/index.db';
    adapter = const SqlCipherRawKeyAdapter();
  });

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('raw key creates and reopens a SQLCipher database', () {
    final key = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 1),
    );
    const fixtureText = 'fixture-search-plaintext-must-not-leak';

    final created = adapter.open(databasePath, rawKey: key);
    created
      ..execute('CREATE TABLE fixture (value TEXT NOT NULL)')
      ..execute('INSERT INTO fixture VALUES (?)', [fixtureText])
      ..close();

    final reopened = adapter.open(databasePath, rawKey: key);
    addTearDown(reopened.close);
    expect(
      reopened.select('SELECT value FROM fixture').single['value'],
      fixtureText,
    );

    final bytes = File(databasePath).readAsBytesSync();
    expect(_contains(bytes, utf8.encode(fixtureText)), isFalse);
    expect(_contains(bytes, key), isFalse);
    expect(_contains(bytes, utf8.encode(_hex(key))), isFalse);
  });

  test('wrong raw key cannot read the schema', () {
    final key = Uint8List(32)..fillRange(0, 32, 0x41);
    final wrongKey = Uint8List(32)..fillRange(0, 32, 0x42);

    adapter.open(databasePath, rawKey: key)
      ..execute('CREATE TABLE fixture (value INTEGER NOT NULL)')
      ..close();

    expect(
      () => adapter.open(databasePath, rawKey: wrongKey),
      throwsA(isA<SqliteException>()),
    );
  });
}

bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  for (var offset = 0; offset <= haystack.length - needle.length; offset++) {
    var matches = true;
    for (var index = 0; index < needle.length; index++) {
      if (haystack[offset + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
