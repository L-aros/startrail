import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'atomic_file_writer.dart';

typedef _CreateFileWNative =
    Pointer<Void> Function(
      Pointer<Utf16>,
      Uint32,
      Uint32,
      Pointer<Void>,
      Uint32,
      Uint32,
      Pointer<Void>,
    );
typedef _CreateFileWDart =
    Pointer<Void> Function(
      Pointer<Utf16>,
      int,
      int,
      Pointer<Void>,
      int,
      int,
      Pointer<Void>,
    );
typedef _FlushFileBuffersNative = Int32 Function(Pointer<Void>);
typedef _FlushFileBuffersDart = int Function(Pointer<Void>);
typedef _CloseHandleNative = Int32 Function(Pointer<Void>);
typedef _CloseHandleDart = int Function(Pointer<Void>);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

const _genericRead = 0x80000000;
const _genericWrite = 0x40000000;
const _fileShareRead = 0x00000001;
const _fileShareWrite = 0x00000002;
const _fileShareDelete = 0x00000004;
const _openExisting = 3;
const _fileFlagBackupSemantics = 0x02000000;

final class WindowsDirectoryDurability implements DirectoryDurability {
  WindowsDirectoryDurability({DynamicLibrary? library})
    : _library = library ?? DynamicLibrary.open('kernel32.dll') {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows directory flush requires Windows');
    }
    _createFile = _library.lookupFunction<_CreateFileWNative, _CreateFileWDart>(
      'CreateFileW',
    );
    _flushFileBuffers = _library
        .lookupFunction<_FlushFileBuffersNative, _FlushFileBuffersDart>(
          'FlushFileBuffers',
        );
    _closeHandle = _library
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
    _getLastError = _library
        .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');
  }

  final DynamicLibrary _library;
  late final _CreateFileWDart _createFile;
  late final _FlushFileBuffersDart _flushFileBuffers;
  late final _CloseHandleDart _closeHandle;
  late final _GetLastErrorDart _getLastError;

  @override
  Future<void> syncDirectory(Directory directory) async {
    final path = directory.path.toNativeUtf16();
    Pointer<Void>? handle;
    try {
      handle = _createFile(
        path,
        _genericRead | _genericWrite,
        _fileShareRead | _fileShareWrite | _fileShareDelete,
        nullptr,
        _openExisting,
        _fileFlagBackupSemantics,
        nullptr,
      );
      if (handle.address == -1) {
        throw FileSystemException(
          'Unable to open directory for flush (Win32 ${_getLastError()})',
        );
      }
      if (_flushFileBuffers(handle) == 0) {
        throw FileSystemException(
          'Unable to flush directory (Win32 ${_getLastError()})',
        );
      }
    } finally {
      if (handle != null && handle.address != -1) _closeHandle(handle);
      malloc.free(path);
    }
  }
}
