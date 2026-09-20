import 'dart:io';

import 'atomic_file_writer.dart';
import 'posix_directory_durability.dart';
import 'windows_directory_durability.dart';

/// Selects the directory metadata durability adapter for a supported target.
DirectoryDurability createDirectoryDurability() {
  if (Platform.isLinux || Platform.isAndroid) {
    return PosixDirectoryDurability();
  }
  if (Platform.isWindows) {
    return WindowsDirectoryDurability();
  }
  throw UnsupportedError('Directory durability is not supported on this OS');
}
