import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// Opens SQLCipher connections using only the native raw-key API.
final class SqlCipherRawKeyAdapter {
  const SqlCipherRawKeyAdapter();

  Database open(
    String path, {
    required Uint8List rawKey,
    OpenMode mode = OpenMode.readWriteCreate,
  }) {
    if (rawKey.length != 32) {
      throw ArgumentError.value(rawKey.length, 'rawKey.length', 'must be 32');
    }

    final database = sqlite3.open(path, mode: mode);
    try {
      database.applySqlCipherRawKey(rawKey);
      database.execute('PRAGMA cipher_memory_security = ON');

      final versionRows = database.select('PRAGMA cipher_version');
      if (versionRows.length != 1 ||
          versionRows.single.values.single is! String ||
          (versionRows.single.values.single as String).isEmpty) {
        throw SqliteException(
          extendedResultCode: 1,
          message: 'SQLCipher is unavailable',
        );
      }

      // Force a page read so an incorrect key fails before the connection is
      // returned to schema or repository code.
      database.select('SELECT count(*) FROM sqlite_master');
      return database;
    } catch (_) {
      database.close();
      rethrow;
    }
  }
}
