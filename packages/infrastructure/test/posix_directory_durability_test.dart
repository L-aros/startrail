import 'dart:io';

import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  test('flushes a real directory on the current platform', () async {
    final directory = await Directory.systemTemp.createTemp('startrail-fsync-');
    addTearDown(() => directory.delete(recursive: true));
    await File(
      '${directory.path}${Platform.pathSeparator}probe',
    ).writeAsBytes([1], flush: true);

    await createDirectoryDurability().syncDirectory(directory);
  });
}
