import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'atomic_file_writer.dart';

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _FsyncNative = Int32 Function(Int32);
typedef _FsyncDart = int Function(int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

const _oDirectory = 0x10000;

final class PosixDirectoryDurability implements DirectoryDurability {
  PosixDirectoryDurability({DynamicLibrary? library})
    : _library = library ?? DynamicLibrary.process() {
    if (!Platform.isLinux && !Platform.isAndroid) {
      throw UnsupportedError('POSIX directory fsync requires Linux or Android');
    }
    _open = _library.lookupFunction<_OpenNative, _OpenDart>('open');
    _fsync = _library.lookupFunction<_FsyncNative, _FsyncDart>('fsync');
    _close = _library.lookupFunction<_CloseNative, _CloseDart>('close');
  }

  final DynamicLibrary _library;
  late final _OpenDart _open;
  late final _FsyncDart _fsync;
  late final _CloseDart _close;

  @override
  Future<void> syncDirectory(Directory directory) async {
    final path = directory.path.toNativeUtf8();
    var descriptor = -1;
    try {
      descriptor = _open(path, _oDirectory);
      if (descriptor < 0) {
        throw FileSystemException(
          'Unable to open directory for fsync',
          directory.path,
        );
      }
      if (_fsync(descriptor) != 0) {
        throw FileSystemException('Unable to fsync directory', directory.path);
      }
    } finally {
      if (descriptor >= 0) _close(descriptor);
      malloc.free(path);
    }
  }
}
