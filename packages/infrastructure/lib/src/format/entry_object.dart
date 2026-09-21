import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';

import 'canonical_json.dart';

/// Wire encoding for `entry` and `tombstone` objects per ADR-0016. The plain
/// text is canonical JSON: `{kind,id,revision,device_id,created_at,payload}`.
final class EntryObjectCodec {
  const EntryObjectCodec();

  Uint8List encodeEntry({
    required String id,
    required int revision,
    required String deviceId,
    required DateTime createdAt,
    required EntryDraft draft,
  }) {
    uuid(id);
    uuid(deviceId);
    _requireRevision(revision);
    return encodeCanonicalJson({
      'kind': 'entry',
      'id': id,
      'revision': revision,
      'device_id': deviceId,
      'created_at': formatTimestamp(createdAt),
      'payload': {
        'body': draft.body,
        'occurred_at': formatTimestamp(draft.occurredAt),
        'mood': draft.mood,
        'tags': [
          for (final tag in draft.tags)
            {'id': tag.id.value, 'name': tag.name, 'color': tag.color},
        ],
        'attachments': [
          for (final a in draft.attachments)
            {
              'id': a.id.value,
              'blob_id': a.blobId.value,
              'mime': a.mime,
              'byte_size': a.byteSize,
              'digest': a.digest,
            },
        ],
      },
    });
  }

  Uint8List encodeTombstone({
    required String id,
    required int revision,
    required String deviceId,
    required DateTime createdAt,
  }) {
    uuid(id);
    uuid(deviceId);
    _requireRevision(revision);
    return encodeCanonicalJson({
      'kind': 'tombstone',
      'id': id,
      'revision': revision,
      'device_id': deviceId,
      'created_at': formatTimestamp(createdAt),
      'payload': <String, Object?>{},
    });
  }

  EntryObject decode(Uint8List plaintext) {
    try {
      final decoded = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (!_bytesEqual(plaintext, encodeCanonicalJson(decoded))) {
        throw const CorruptVaultDataFailure();
      }
      _expectKeys(decoded, const {
        'kind',
        'id',
        'revision',
        'device_id',
        'created_at',
        'payload',
      });
      final id = decoded['id'];
      final revision = decoded['revision'];
      final deviceId = decoded['device_id'];
      final createdAt = decoded['created_at'];
      final payload = decoded['payload'];
      if (id is! String || deviceId is! String || createdAt is! String) {
        throw const FormatException();
      }
      uuid(id);
      uuid(deviceId);
      _requireRevision(revision);
      final occurredAt = parseTimestamp(createdAt);
      final kind = decoded['kind'];
      if (kind == 'entry') {
        return EntryRecord(
          id: id,
          revision: revision,
          deviceId: deviceId,
          createdAt: occurredAt,
          entry: _decodeEntryPayload(id, revision, payload),
        );
      }
      if (kind == 'tombstone') {
        if (payload is! Map || payload.isNotEmpty) {
          throw const UnsupportedVaultFormatFailure();
        }
        return TombstoneRecord(
          id: id,
          revision: revision,
          deviceId: deviceId,
          createdAt: occurredAt,
        );
      }
      throw const UnsupportedVaultFormatFailure();
    } on VaultFailure {
      rethrow;
    } on Object {
      throw const CorruptVaultDataFailure();
    }
  }

  Entry _decodeEntryPayload(String id, int revision, Object? payload) {
    if (payload is! Map<String, dynamic>) throw const FormatException();
    _expectKeys(payload, const {
      'body',
      'occurred_at',
      'mood',
      'tags',
      'attachments',
    });
    final body = payload['body'];
    final mood = payload['mood'];
    final tagsJson = payload['tags'];
    final attachmentsJson = payload['attachments'];
    if (body is! String || mood is! String? || mood is num || mood is bool) {
      throw const FormatException();
    }
    final tags = <Tag>[for (final raw in _list(tagsJson)) _decodeTag(raw)];
    final attachments = <Attachment>[
      for (final raw in _list(attachmentsJson)) _decodeAttachment(raw),
    ];
    final entry = Entry(
      id: EntryId(id),
      revision: revision,
      occurredAt: parseTimestamp(payload['occurred_at'] as String),
      body: body,
      mood: mood,
      tags: tags,
      attachments: attachments,
    );
    return entry;
  }

  Tag _decodeTag(Object? raw) {
    if (raw is! Map<String, dynamic>) throw const FormatException();
    _expectKeys(raw, const {'id', 'name', 'color'});
    final id = raw['id'];
    final name = raw['name'];
    final color = raw['color'];
    if (id is! String || name is! String || color is! int) {
      throw const FormatException();
    }
    return Tag(id: TagId(id), name: name, color: color);
  }

  Attachment _decodeAttachment(Object? raw) {
    if (raw is! Map<String, dynamic>) throw const FormatException();
    _expectKeys(raw, const {'id', 'blob_id', 'mime', 'byte_size', 'digest'});
    final id = raw['id'];
    final blobId = raw['blob_id'];
    final mime = raw['mime'];
    final byteSize = raw['byte_size'];
    final digest = raw['digest'];
    if (id is! String ||
        blobId is! String ||
        mime is! String ||
        byteSize is! int ||
        digest is! String) {
      throw const FormatException();
    }
    return Attachment(
      id: AttachmentId(id),
      blobId: BlobId(blobId),
      mime: mime,
      byteSize: byteSize,
      digest: digest,
    );
  }

  List<Object?> _list(Object? value) {
    if (value is! List) throw const FormatException();
    return value;
  }
}

sealed class EntryObject {
  const EntryObject();

  String get id;
  int get revision;
}

final class EntryRecord extends EntryObject {
  const EntryRecord({
    required this.id,
    required this.revision,
    required this.deviceId,
    required this.createdAt,
    required this.entry,
  });

  @override
  final String id;
  @override
  final int revision;
  final String deviceId;
  final DateTime createdAt;
  final Entry entry;
}

final class TombstoneRecord extends EntryObject {
  const TombstoneRecord({
    required this.id,
    required this.revision,
    required this.deviceId,
    required this.createdAt,
  });

  @override
  final String id;
  @override
  final int revision;
  final String deviceId;
  final DateTime createdAt;
}

/// Formats a timestamp as RFC 3339 UTC with exactly 3 fractional digits.
String formatTimestamp(DateTime value) {
  final utc = value.toUtc();
  String digits(int number, int width) => number.toString().padLeft(width, '0');
  return '${digits(utc.year, 4)}-${digits(utc.month, 2)}-'
      '${digits(utc.day, 2)}T${digits(utc.hour, 2)}:'
      '${digits(utc.minute, 2)}:${digits(utc.second, 2)}.'
      '${digits(utc.millisecond, 3)}Z';
}

/// Parses an RFC 3339 UTC timestamp with exactly 3 fractional digits.
DateTime parseTimestamp(String value) {
  if (!_timestamp.hasMatch(value)) throw const FormatException();
  return DateTime.parse(value);
}

final _timestamp = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');

void uuid(String value) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  ).hasMatch(value)) {
    throw const FormatException('UUID must be lowercase canonical text');
  }
}

void _requireRevision(Object? revision) {
  if (revision is! int || revision < 1) throw const FormatException();
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
