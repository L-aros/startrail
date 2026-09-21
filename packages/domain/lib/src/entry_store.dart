import 'entry.dart';

/// Requested entry does not exist or has been deleted.
final class EntryNotFound implements Exception {
  const EntryNotFound(this.id);

  final EntryId id;

  @override
  String toString() => 'EntryNotFound($id)';
}

/// The caller's base revision no longer matches the current head.
final class EntryRevisionConflict implements Exception {
  const EntryRevisionConflict(this.id, this.expected, this.actual);

  final EntryId id;
  final int expected;
  final int actual;

  @override
  String toString() =>
      'EntryRevisionConflict($id expected=$expected actual=$actual)';
}

/// Port implemented by the infrastructure Vault adapter. Domain and
/// application layers depend on this interface only, never on storage.
abstract interface class EntryStore {
  /// Persists a brand-new entry, returning the created entity.
  Future<Entry> createEntry(EntryDraft draft);

  /// Replaces an existing entry when [expectedRevision] matches the current
  /// head; otherwise throws [EntryRevisionConflict].
  Future<Entry> updateEntry(EntryId id, int expectedRevision, EntryDraft draft);

  /// Marks an entry deleted via a tombstone when [expectedRevision] matches.
  Future<void> deleteEntry(EntryId id, int expectedRevision);

  /// Returns active entries ordered by `occurred_at` descending.
  Future<List<Entry>> timeline();

  /// Returns active entries whose body matches [query] after normalization.
  Future<List<Entry>> searchEntries(String query);

  /// Returns every distinct tag across active entries.
  Future<List<Tag>> listTags();
}
