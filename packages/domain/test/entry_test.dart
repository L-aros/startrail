import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  const entryId = '11111111-1111-4111-8111-111111111111';
  const tagId = '22222222-2222-4222-8222-222222222222';
  const attachmentId = '33333333-3333-4333-8333-333333333333';
  const blobId = 'abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrst';
  const digest = 'sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  group('Uuid', () {
    test('accepts canonical lowercase UUID', () {
      expect(Uuid(entryId).value, entryId);
    });

    test('rejects malformed values', () {
      expect(() => Uuid('nope'), throwsArgumentError);
      expect(
        () => Uuid('11111111-1111-4111-8111-11111111111G'),
        throwsArgumentError,
      );
    });
  });

  group('BlobId', () {
    test('accepts 52-char base32', () {
      expect(BlobId(blobId).value, blobId);
    });

    test('rejects wrong length or alphabet', () {
      expect(() => BlobId('abc'), throwsArgumentError);
      expect(() => BlobId(blobId.replaceFirst('a', '0')), throwsArgumentError);
    });
  });

  group('Tag', () {
    test('accepts valid tag', () {
      final tag = Tag(id: const TagId(tagId), name: '旅行', color: 0x00ff0000);
      expect(tag.name, '旅行');
      expect(tag.color, 0x00ff0000);
    });

    test('rejects empty name and out-of-range color', () {
      expect(
        () => Tag(id: const TagId(tagId), name: '', color: 1),
        throwsArgumentError,
      );
      expect(
        () => Tag(id: const TagId(tagId), name: 'x', color: -1),
        throwsArgumentError,
      );
      expect(
        () => Tag(id: const TagId(tagId), name: 'x', color: 0x100000000),
        throwsArgumentError,
      );
    });
  });

  group('Attachment', () {
    test('accepts valid attachment', () {
      final a = Attachment(
        id: const AttachmentId(attachmentId),
        blobId: BlobId(blobId),
        mime: 'image/jpeg',
        byteSize: 1024,
        digest: digest,
      );
      expect(a.byteSize, 1024);
    });

    test('rejects oversized and invalid digest', () {
      expect(
        () => Attachment(
          id: const AttachmentId(attachmentId),
          blobId: BlobId(blobId),
          mime: 'image/jpeg',
          byteSize: maxAttachmentBytes + 1,
          digest: digest,
        ),
        throwsArgumentError,
      );
      expect(
        () => Attachment(
          id: const AttachmentId(attachmentId),
          blobId: BlobId(blobId),
          mime: 'image/jpeg',
          byteSize: 1,
          digest: 'sha256:short',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Entry body and mood limits', () {
    test('rejects body over 1 MiB', () {
      final big = 'a' * (maxEntryBodyBytes + 1);
      expect(
        () => EntryDraft(
          occurredAt: DateTime.utc(2026),
          body: big,
          mood: null,
          tags: const [],
          attachments: const [],
        ),
        throwsArgumentError,
      );
    });

    test('rejects mood over 64 bytes', () {
      expect(
        () => EntryDraft(
          occurredAt: DateTime.utc(2026),
          body: 'ok',
          mood: '嗯' * 40,
          tags: const [],
          attachments: const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('normalizeTagName', () {
    test('trims, lowercases and collapses whitespace', () {
      expect(normalizeTagName('  旅行  日记 '), '旅行 日记');
      expect(normalizeTagName('Travel'), 'travel');
    });
  });
}
