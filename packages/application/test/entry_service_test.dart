import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('EntryService', () {
    test('rejects duplicate normalized tags', () async {
      final service = EntryService(_FakeStore());
      final draft = EntryDraft(
        occurredAt: DateTime.utc(2026, 9, 21),
        body: 'ok',
        mood: null,
        tags: [
          Tag(
            id: const TagId('22222222-2222-4222-8222-222222222222'),
            name: '旅行',
            color: 1,
          ),
          Tag(
            id: const TagId('33333333-3333-4333-8333-333333333333'),
            name: ' 旅行 ',
            color: 2,
          ),
        ],
        attachments: const [],
      );

      await expectLater(
        service.createEntry(draft),
        throwsA(isA<DuplicateTagError>()),
      );
    });

    test('maps missing entry to a stable error', () async {
      final service = EntryService(_FakeStore());
      await expectLater(
        service.deleteEntry(
          const EntryId('11111111-1111-4111-8111-111111111111'),
          1,
        ),
        throwsA(isA<EntryNotFoundError>()),
      );
    });

    test('delegates timeline and tags', () async {
      final store = _FakeStore();
      final service = EntryService(store);
      expect(await service.timeline(), isEmpty);
      expect(await service.tags(), isEmpty);
      expect(await service.search('x'), isEmpty);
    });
  });
}

final class _FakeStore implements EntryStore {
  @override
  Future<Entry> createEntry(EntryDraft draft) async =>
      throw const EntryNotFound(
        EntryId('11111111-1111-4111-8111-111111111111'),
      );

  @override
  Future<void> deleteEntry(EntryId id, int expectedRevision) async =>
      throw const EntryNotFound(
        EntryId('11111111-1111-4111-8111-111111111111'),
      );

  @override
  Future<List<Tag>> listTags() async => const [];

  @override
  Future<List<Entry>> searchEntries(String query) async => const [];

  @override
  Future<List<Entry>> timeline() async => const [];

  @override
  Future<Entry> updateEntry(
    EntryId id,
    int expectedRevision,
    EntryDraft draft,
  ) async => throw const EntryNotFound(
    EntryId('11111111-1111-4111-8111-111111111111'),
  );
}
