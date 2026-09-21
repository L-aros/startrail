import 'package:application/application.dart';
import 'package:test/test.dart';

void main() {
  test('application error codes are stable and non-sensitive', () {
    expect(const EntryNotFoundError().code, 'ENTRY_NOT_FOUND');
    expect(const EntryConflictError().code, 'ENTRY_CONFLICT');
    expect(const DuplicateTagError().code, 'DUPLICATE_TAG');
    expect(const EntryValidationError().code, 'ENTRY_INVALID');
  });
}
