import 'dart:typed_data';

import 'canonical_json.dart';
import 'vault_header.dart';

Uint8List encodeInitialManifest({
  required String writerDeviceId,
  required DateTime createdAt,
}) {
  uuidBytes(writerDeviceId);
  final timestamp = _formatTimestamp(createdAt);
  return encodeCanonicalJson({
    'created_at': timestamp,
    'entities': <String, Object?>{},
    'format': 1,
    'known_devices': {
      writerDeviceId: {'last_seen_at': timestamp},
    },
    'parent_ids': <Object?>[],
    'writer_device_id': writerDeviceId,
  });
}

String _formatTimestamp(DateTime value) {
  final utc = value.toUtc();
  String digits(int number, int width) => number.toString().padLeft(width, '0');
  return '${digits(utc.year, 4)}-${digits(utc.month, 2)}-'
      '${digits(utc.day, 2)}T${digits(utc.hour, 2)}:'
      '${digits(utc.minute, 2)}:${digits(utc.second, 2)}.'
      '${digits(utc.millisecond, 3)}Z';
}
