import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:sqlite3/src/ffi/raw_key_memory.dart';
import 'package:test/test.dart';

void main() {
  for (final shouldThrow in [false, true]) {
    test('native key copy is cleared when operation throws: $shouldThrow', () {
      final allocator = _RecordingAllocator(4);
      final source = Uint8List.fromList([1, 2, 3, 4]);

      Object? error;
      try {
        withClearedNativeBytes(source, (pointer) {
          expect(pointer.asTypedList(4), source);
          if (shouldThrow) throw StateError('fixture failure');
          return 0;
        }, allocator: allocator);
      } catch (caught) {
        error = caught;
      }

      expect(error, shouldThrow ? isA<StateError>() : isNull);
      expect(allocator.bytesBeforeFree, [0, 0, 0, 0]);
      expect(source, [1, 2, 3, 4]);
    });
  }
}

final class _RecordingAllocator implements Allocator {
  _RecordingAllocator(this.length);

  final int length;
  List<int>? bytesBeforeFree;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) =>
      calloc.allocate<T>(byteCount, alignment: alignment);

  @override
  void free(Pointer<NativeType> pointer) {
    bytesBeforeFree = pointer.cast<Uint8>().asTypedList(length).toList();
    calloc.free(pointer);
  }
}
