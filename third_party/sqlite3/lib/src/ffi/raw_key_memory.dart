import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Runs [operation] with a native copy of [bytes] and overwrites the copy
/// before releasing it, including when [operation] throws.
T withClearedNativeBytes<T>(
  Uint8List bytes,
  T Function(Pointer<Uint8> bytes) operation, {
  Allocator allocator = malloc,
}) {
  if (bytes.isEmpty) {
    throw ArgumentError.value(bytes.length, 'bytes.length', 'must be non-zero');
  }
  final pointer = allocator.allocate<Uint8>(bytes.length);
  final nativeBytes = pointer.asTypedList(bytes.length);
  nativeBytes.setAll(0, bytes);
  try {
    return operation(pointer);
  } finally {
    nativeBytes.fillRange(0, nativeBytes.length, 0);
    allocator.free(pointer);
  }
}
