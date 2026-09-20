/// Stable, non-sensitive failures exposed across application boundaries.
sealed class VaultFailure implements Exception {
  const VaultFailure(this.code);

  final String code;

  @override
  String toString() => code;
}

final class VaultAuthenticationFailure extends VaultFailure {
  const VaultAuthenticationFailure() : super('VAULT_AUTH_FAILED');
}

final class UnsupportedVaultFormatFailure extends VaultFailure {
  const UnsupportedVaultFormatFailure() : super('VAULT_FORMAT_UNSUPPORTED');
}

final class CorruptVaultDataFailure extends VaultFailure {
  const CorruptVaultDataFailure() : super('VAULT_DATA_CORRUPT');
}
