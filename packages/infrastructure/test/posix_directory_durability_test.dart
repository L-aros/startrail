import 'dart:io';

import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  test('fsyncs a real directory on supported POSIX platforms', () async {
    if (!Platform.isLinux && !Platform.isAndroid) return;
    final directory = await Directory.systemTemp.createTemp('startrail-fsync-');
    addTearDown(() => directory.delete(recursive: true));
    await File(
      '${directory.path}${Platform.pathSeparator}probe',
    ).writeAsBytes([1], flush: true);

    await PosixDirectoryDurability().syncDirectory(directory);
  });
}
