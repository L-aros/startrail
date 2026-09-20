import 'dart:convert';
import 'dart:typed_data';

/// Encodes JSON with recursively sorted object keys and no extra whitespace.
Uint8List encodeCanonicalJson(Object? value) {
  final normalized = _normalize(value);
  return Uint8List.fromList(utf8.encode(jsonEncode(normalized)));
}

Object? _normalize(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _normalize(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map(_normalize).toList(growable: false);
  }
  if (value == null || value is bool || value is String || value is num) {
    return value;
  }
  throw ArgumentError.value(value, 'value', 'is not a JSON value');
}
