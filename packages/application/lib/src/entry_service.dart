import 'package:domain/domain.dart';

/// Stable, non-sensitive application error codes for the presentation layer.
sealed class EntryError implements Exception {
  const EntryError(this.code);

  final String code;

  @override
  String toString() => code;
}

final class EntryNotFoundError extends EntryError {
  const EntryNotFoundError() : super('ENTRY_NOT_FOUND');
}

final class EntryConflictError extends EntryError {
  const EntryConflictError() : super('ENTRY_CONFLICT');
}

final class DuplicateTagError extends EntryError {
  const DuplicateTagError() : super('DUPLICATE_TAG');
}

final class EntryValidationError extends EntryError {
  const EntryValidationError() : super('ENTRY_INVALID');
}

/// Use cases for recording, editing, browsing and searching entries.
///
/// Owns application-level validation (tag de-duplication) and maps domain and
/// infrastructure failures to stable [EntryError] codes so the UI never sees
/// storage internals.
final class EntryService {
  EntryService(this._store);

  final EntryStore _store;

  Future<Entry> createEntry(EntryDraft draft) async {
    try {
      _validateTags(draft.tags);
      return await _store.createEntry(draft);
    } on EntryNotFound {
      throw const EntryNotFoundError();
    } on EntryRevisionConflict {
      throw const EntryConflictError();
    } on ArgumentError {
      throw const EntryValidationError();
    }
  }

  Future<Entry> updateEntry(
    EntryId id,
    int expectedRevision,
    EntryDraft draft,
  ) async {
    try {
      _validateTags(draft.tags);
      return await _store.updateEntry(id, expectedRevision, draft);
    } on EntryNotFound {
      throw const EntryNotFoundError();
    } on EntryRevisionConflict {
      throw const EntryConflictError();
    } on ArgumentError {
      throw const EntryValidationError();
    }
  }

  Future<void> deleteEntry(EntryId id, int expectedRevision) async {
    try {
      await _store.deleteEntry(id, expectedRevision);
    } on EntryNotFound {
      throw const EntryNotFoundError();
    } on EntryRevisionConflict {
      throw const EntryConflictError();
    }
  }

  Future<List<Entry>> timeline() => _store.timeline();

  Future<List<Entry>> search(String query) => _store.searchEntries(query);

  Future<List<Tag>> tags() => _store.listTags();

  void _validateTags(List<Tag> tags) {
    final seen = <String>{};
    for (final tag in tags) {
      final normalized = normalizeTagName(tag.name);
      if (normalized.isEmpty) throw const EntryValidationError();
      if (!seen.add(normalized)) throw const DuplicateTagError();
    }
  }
}
