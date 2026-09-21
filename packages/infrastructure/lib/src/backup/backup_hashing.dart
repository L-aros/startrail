import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

/// Incremental SHA-256 that accepts chunks and returns the 32-byte digest on
/// [close], without buffering the entire input.
final class StreamingSha256 {
  final _DigestSink _sink = _DigestSink();
  late final ByteConversionSink _input = sha256.startChunkedConversion(_sink);

  void add(List<int> bytes) => _input.add(bytes);

  Uint8List close() {
    _input.close();
    final digest = _sink.digest;
    if (digest == null) throw StateError('SHA-256 sink produced no digest');
    return Uint8List.fromList(digest.bytes);
  }
}
