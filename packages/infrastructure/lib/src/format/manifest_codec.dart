import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';

import 'canonical_json.dart';
import 'entry_object.dart';

/// Decoded Manifest v1 as a mutable in-memory structure for update transactions.
final class ManifestV1 {
  ManifestV1({
    required Map<String, List<String>> entities,
    required List<String> parentIds,
    required this.writerDeviceId,
    required this.createdAt,
    required Map<String, DateTime> knownDevices,
  }) : entities = Map.unmodifiable(entities),
       parentIds = List.unmodifiable(parentIds),
       knownDevices = Map.unmodifiable(knownDevices);

  final Map<String, List<String>> entities;
  final List<String> parentIds;
  final String writerDeviceId;
  final DateTime createdAt;
  final Map<String, DateTime> knownDevices;

  ManifestV1 copyWith({
    Map<String, List<String>>? entities,
    List<String>? parentIds,
    String? writerDeviceId,
    DateTime? createdAt,
    Map<String, DateTime>? knownDevices,
  }) {
    return ManifestV1(
      entities: entities ?? this.entities,
      parentIds: parentIds ?? this.parentIds,
      writerDeviceId: writerDeviceId ?? this.writerDeviceId,
      createdAt: createdAt ?? this.createdAt,
      knownDevices: knownDevices ?? this.knownDevices,
    );
  }
}

final class ManifestV1Codec {
  const ManifestV1Codec();

  Uint8List encode(ManifestV1 manifest) => encodeCanonicalJson({
    'created_at': formatTimestamp(manifest.createdAt),
    'entities': {
      for (final entry in manifest.entities.entries)
        entry.key: {'heads': entry.value},
    },
    'format': 1,
    'known_devices': {
      for (final device in manifest.knownDevices.entries)
        device.key: {'last_seen_at': formatTimestamp(device.value)},
    },
    'parent_ids': manifest.parentIds,
    'writer_device_id': manifest.writerDeviceId,
  });

  ManifestV1 decode(Uint8List plaintext) {
    try {
      final decoded = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (!_bytesEqual(plaintext, encodeCanonicalJson(decoded))) {
        throw const CorruptVaultDataFailure();
      }
      _expectKeys(decoded, const {
        'created_at',
        'entities',
        'format',
        'known_devices',
        'parent_ids',
        'writer_device_id',
      });
      if (decoded['format'] != 1) {
        throw const UnsupportedVaultFormatFailure();
      }
      final writerDeviceId = decoded['writer_device_id'];
      if (writerDeviceId is! String) throw const FormatException();
      uuid(writerDeviceId);

      final createdAt = parseTimestamp(decoded['created_at'] as String);
      final parentIds = _decodeParentIds(decoded['parent_ids']);
      final entities = _decodeEntities(decoded['entities']);
      final knownDevices = _decodeKnownDevices(decoded['known_devices']);

      return ManifestV1(
        entities: entities,
        parentIds: parentIds,
        writerDeviceId: writerDeviceId,
        createdAt: createdAt,
        knownDevices: knownDevices,
      );
    } on VaultFailure {
      rethrow;
    } on Object {
      throw const CorruptVaultDataFailure();
    }
  }

  List<String> _decodeParentIds(Object? value) {
    if (value is! List || value.any((e) => e is! String)) {
      throw const FormatException();
    }
    return value.cast<String>();
  }

  Map<String, List<String>> _decodeEntities(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    final result = <String, List<String>>{};
    for (final entry in value.entries) {
      uuid(entry.key);
      final heads = entry.value;
      if (heads is! Map<String, dynamic>) throw const FormatException();
      _expectKeys(heads, const {'heads'});
      final list = heads['heads'];
      if (list is! List || list.any((e) => e is! String)) {
        throw const FormatException();
      }
      result[entry.key] = list.cast<String>();
    }
    return result;
  }

  Map<String, DateTime> _decodeKnownDevices(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    final result = <String, DateTime>{};
    for (final entry in value.entries) {
      uuid(entry.key);
      final device = entry.value;
      if (device is! Map<String, dynamic>) throw const FormatException();
      _expectKeys(device, const {'last_seen_at'});
      result[entry.key] = parseTimestamp(device['last_seen_at'] as String);
    }
    return result;
  }
}

void _expectKeys(Map<String, dynamic> value, Set<String> keys) {
  if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
    throw const UnsupportedVaultFormatFailure();
  }
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
