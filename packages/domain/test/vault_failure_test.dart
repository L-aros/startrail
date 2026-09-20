import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('authentication errors expose one non-sensitive stable code', () {
    const failure = VaultAuthenticationFailure();

    expect(failure.code, 'VAULT_AUTH_FAILED');
    expect(failure.toString(), 'VAULT_AUTH_FAILED');
  });
}
