import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  const codec = EntryObjectCodec();
  const entryId = '11111111-1111-4111-8111-111111111111';
  const deviceId = '99999999-9999-4999-8999-999999999999';
  const tagId = '22222222-2222-4222-8222-222222222222';
  const attachmentId = '33333333-3333-4333-8333-333333333333';
  const blobId = 'abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrst';
  const digest = 'sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  final occurredAt = DateTime.utc(2026, 9, 20, 8, 30);
  final createdAt = DateTime.utc(2026, 9, 21, 12, 34, 56, 789);

  EntryDraft draft() => EntryDraft(
    occurredAt: occurredAt,
    body: '今天去了海边',
    mood: 'happy',
    tags: [Tag(id: const TagId(tagId), name: '旅行', color: 0x00ff0000)],
    attachments: [
      Attachment(
        id: const AttachmentId(attachmentId),
        blobId: BlobId(blobId),
        mime: 'image/jpeg',
        byteSize: 123456,
        digest: digest,
      ),
    ],
  );

  test('entry roundtrip preserves every field', () {
    final bytes = codec.encodeEntry(
      id: entryId,
      revision: 1,
      deviceId: deviceId,
      createdAt: createdAt,
      draft: draft(),
    );

    final decoded = codec.decode(bytes);
    expect(decoded, isA<EntryRecord>());
    final record = decoded as EntryRecord;
    expect(record.id, entryId);
    expect(record.revision, 1);
    expect(record.deviceId, deviceId);
    expect(record.createdAt, createdAt);
    expect(record.entry.body, '今天去了海边');
    expect(record.entry.mood, 'happy');
    expect(record.entry.occurredAt, occurredAt);
    expect(record.entry.tags.single.name, '旅行');
    expect(record.entry.attachments.single.byteSize, 123456);
    expect(record.entry.attachments.single.blobId.value, blobId);
  });

  test('tombstone roundtrip', () {
    final bytes = codec.encodeTombstone(
      id: entryId,
      revision: 2,
      deviceId: deviceId,
      createdAt: createdAt,
    );

    final decoded = codec.decode(bytes);
    expect(decoded, isA<TombstoneRecord>());
    final record = decoded as TombstoneRecord;
    expect(record.id, entryId);
    expect(record.revision, 2);
    expect(record.deviceId, deviceId);
  });

  test('rejects unknown kind', () {
    final bytes = codec.encodeEntry(
      id: entryId,
      revision: 1,
      deviceId: deviceId,
      createdAt: createdAt,
      draft: draft(),
    );
    final text = String.fromCharCodes(bytes).replaceFirst('entry', 'photo');
    expect(
      () => codec.decode(Uint8List.fromList(text.codeUnits)),
      throwsA(isA<UnsupportedVaultFormatFailure>()),
    );
  });

  test('rejects non-canonical encoding', () {
    final bytes = codec.encodeEntry(
      id: entryId,
      revision: 1,
      deviceId: deviceId,
      createdAt: createdAt,
      draft: draft(),
    );
    // Append a trailing space to break canonicality.
    final tampered = Uint8List.fromList([...bytes, 0x20]);
    expect(() => codec.decode(tampered), throwsA(isA<VaultFailure>()));
  });

  test('rejects unknown payload field', () {
    final bytes = codec.encodeEntry(
      id: entryId,
      revision: 1,
      deviceId: deviceId,
      createdAt: createdAt,
      draft: draft(),
    );
    final text = String.fromCharCodes(
      bytes,
    ).replaceFirst('"body"', '"extra","body"');
    expect(
      () => codec.decode(Uint8List.fromList(text.codeUnits)),
      throwsA(isA<UnsupportedVaultFormatFailure>()),
    );
  });

  test('formatTimestamp produces exactly 3 fractional digits', () {
    expect(
      formatTimestamp(DateTime.utc(2026, 9, 21, 12, 34, 56, 789)),
      '2026-09-21T12:34:56.789Z',
    );
    expect(
      formatTimestamp(DateTime.utc(2026, 1, 2, 3, 4, 5, 6)),
      '2026-01-02T03:04:05.006Z',
    );
  });
}
