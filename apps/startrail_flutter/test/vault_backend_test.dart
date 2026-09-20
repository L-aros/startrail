import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:startrail/src/vault_backend.dart';

void main() {
  test('creates, locks, and unlocks in a worker isolate', () async {
    final sandbox = await Directory.systemTemp.createTemp('拾星迹 worker ');
    final vault = '${sandbox.path}${Platform.pathSeparator}加密 Vault';
    final backend = IsolateVaultBackend();
    addTearDown(() async {
      await backend.lock();
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    final password = Int8List.fromList('correct password'.codeUnits);
    expect(await backend.create(vault, password), isNull);
    await backend.lock();

    final wrong = Int8List.fromList('wrong password'.codeUnits);
    expect(await backend.unlock(vault, wrong), 'VAULT_AUTH_FAILED');
    expect(await backend.unlock(vault, password), isNull);
  });
}
