import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('bundled SQLite engine is SQLCipher-enabled', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.close);

    final rows = database.select('PRAGMA cipher_version');

    expect(rows, hasLength(1));
    expect(rows.first.values.single, isA<String>());
    expect(rows.first.values.single as String, isNotEmpty);
  });
}
