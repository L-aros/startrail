import 'dart:convert';

/// Maximum UTF-8 byte length of an entry body (1 MiB).
const int maxEntryBodyBytes = 1024 * 1024;

/// Maximum UTF-8 byte length of an optional mood value.
const int maxMoodBytes = 64;

/// Default per-attachment size ceiling (250 MiB); may be lowered by settings.
const int maxAttachmentBytes = 250 * 1024 * 1024;

/// A random RFC 4122 UUID v4 in lowercase canonical text form.
final class Uuid {
  Uuid(this.value) {
    if (!_uuid.hasMatch(value)) {
      throw ArgumentError.value(value, 'value', 'not a canonical UUID v4');
    }
  }

  final String value;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  @override
  bool operator ==(Object other) => other is Uuid && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Stable identifier of a logical entry entity, unchanged across revisions.
final class EntryId {
  const EntryId(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is EntryId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class TagId {
  const TagId(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is TagId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class AttachmentId {
  const AttachmentId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is AttachmentId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Identifier of an immutable encrypted blob object, 52-char lowercase base32.
final class BlobId {
  BlobId(this.value) {
    if (!_base32.hasMatch(value)) {
      throw ArgumentError.value(value, 'value', 'not a 52-char base32 id');
    }
  }

  final String value;

  static final _base32 = RegExp(r'^[a-z2-7]{52}$');

  @override
  bool operator ==(Object other) => other is BlobId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A user label attached to entries. Embedded verbatim in entry objects.
final class Tag {
  Tag({required this.id, required this.name, required this.color}) {
    if (name.isEmpty) throw ArgumentError.value(name, 'name', 'empty');
    if (color < 0 || color > 0xffffffff) {
      throw ArgumentError.value(color, 'color', 'out of range');
    }
  }

  final TagId id;
  final String name;
  final int color;

  @override
  bool operator ==(Object other) =>
      other is Tag &&
      other.id == id &&
      other.name == name &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, name, color);
}

/// Metadata for a media attachment; the bytes live in a separate blob object.
final class Attachment {
  Attachment({
    required this.id,
    required this.blobId,
    required this.mime,
    required this.byteSize,
    required this.digest,
  }) {
    if (mime.isEmpty) throw ArgumentError.value(mime, 'mime', 'empty');
    if (byteSize <= 0 || byteSize > maxAttachmentBytes) {
      throw ArgumentError.value(byteSize, 'byteSize', 'out of range');
    }
    if (!_digest.hasMatch(digest)) {
      throw ArgumentError.value(digest, 'digest', 'not sha256:<base64url>');
    }
  }

  final AttachmentId id;
  final BlobId blobId;
  final String mime;
  final int byteSize;
  final String digest;

  static final _digest = RegExp(r'^sha256:[A-Za-z0-9_-]{43}$');

  @override
  bool operator ==(Object other) =>
      other is Attachment &&
      other.id == id &&
      other.blobId == blobId &&
      other.mime == mime &&
      other.byteSize == byteSize &&
      other.digest == digest;

  @override
  int get hashCode => Object.hash(id, blobId, mime, byteSize, digest);
}

/// A persisted entry: the current active head of a logical entry entity.
final class Entry {
  Entry({
    required this.id,
    required this.revision,
    required this.occurredAt,
    required this.body,
    required this.mood,
    required List<Tag> tags,
    required List<Attachment> attachments,
  }) : tags = List.unmodifiable(tags),
       attachments = List.unmodifiable(attachments) {
    if (revision < 1) throw ArgumentError.value(revision, 'revision', '< 1');
    _requireBody(body);
    _requireMood(mood);
  }

  final EntryId id;
  final int revision;
  final DateTime occurredAt;
  final String body;
  final String? mood;
  final List<Tag> tags;
  final List<Attachment> attachments;
}

/// Unvalidated content the user wants to persist. No id or revision yet.
final class EntryDraft {
  EntryDraft({
    required this.occurredAt,
    required this.body,
    required this.mood,
    required List<Tag> tags,
    required List<Attachment> attachments,
  }) : tags = List.unmodifiable(tags),
       attachments = List.unmodifiable(attachments) {
    _requireBody(body);
    _requireMood(mood);
  }

  final DateTime occurredAt;
  final String body;
  final String? mood;
  final List<Tag> tags;
  final List<Attachment> attachments;
}

/// Lowercases, trims and collapses internal whitespace for tag de-duplication.
String normalizeTagName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

void _requireBody(String body) {
  if (utf8.encode(body).length > maxEntryBodyBytes) {
    throw ArgumentError.value(body.length, 'body', 'exceeds 1 MiB');
  }
}

void _requireMood(String? mood) {
  if (mood != null &&
      (mood.isEmpty || utf8.encode(mood).length > maxMoodBytes)) {
    throw ArgumentError.value(mood.length, 'mood', 'invalid length');
  }
}
