import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';

import 'canonical_json.dart';
import 'vault_header.dart';

void validateManifestV1(Uint8List plaintext) {
  try {
    final decoded = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    if (!_equal(plaintext, encodeCanonicalJson(decoded))) {
      throw const CorruptVaultDataFailure();
    }
    const keys = {
      'created_at',
      'entities',
      'format',
      'known_devices',
      'parent_ids',
      'writer_device_id',
    };
    if (decoded.length != keys.length ||
        !decoded.keys.toSet().containsAll(keys)) {
      throw const UnsupportedVaultFormatFailure();
    }
    if (decoded['format'] != 1) throw const UnsupportedVaultFormatFailure();
    final timestamp = decoded['created_at'];
    if (timestamp is! String || !_timestamp.hasMatch(timestamp)) {
      throw const FormatException();
    }
    final writer = decoded['writer_device_id'];
    if (writer is! String) throw const FormatException();
    uuidBytes(writer);
    final parents = decoded['parent_ids'];
    if (parents is! List || parents.any((value) => value is! String)) {
      throw const FormatException();
    }
    if (decoded['entities'] is! Map<String, dynamic>) {
      throw const FormatException();
    }
    final devices = decoded['known_devices'];
    if (devices is! Map<String, dynamic>) throw const FormatException();
    for (final entry in devices.entries) {
      uuidBytes(entry.key);
      final device = entry.value;
      if (device is! Map<String, dynamic> ||
          device.length != 1 ||
          device['last_seen_at'] is! String ||
          !_timestamp.hasMatch(device['last_seen_at'] as String)) {
        throw const FormatException();
      }
    }
  } on VaultFailure {
    rethrow;
  } on Object {
    throw const CorruptVaultDataFailure();
  }
}

final _timestamp = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');

bool _equal(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
