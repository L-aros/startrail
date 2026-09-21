/// Outcome of an isolated backup verification.
enum BackupVerificationStatus {
  /// The backup is authentic, complete and internally consistent.
  ok,

  /// The supplied password does not unwrap the backup key.
  wrongPassword,

  /// The password is correct but the backup bytes were modified.
  tampered,

  /// The backup is structurally malformed or truncated.
  corrupt,

  /// The backup uses an unknown or downgraded format version.
  unsupported,
}

/// Non-sensitive summary produced by isolated verification. For a non-[ok]
/// result only [status] is meaningful; the other fields are left unset.
final class BackupVerificationReport {
  const BackupVerificationReport({
    required this.status,
    this.vaultUuid,
    this.fileCount = 0,
    this.objectCount = 0,
    this.totalBytes = 0,
    this.rootDigest,
  });

  final BackupVerificationStatus status;
  final String? vaultUuid;
  final int fileCount;
  final int objectCount;
  final int totalBytes;

  /// `sha256:<base64url>` of the manifest ciphertext; a stable fingerprint for
  /// comparing backup copies across devices.
  final String? rootDigest;

  bool get isOk => status == BackupVerificationStatus.ok;
}

/// Summary of a successfully created encrypted backup artifact.
final class BackupSummary {
  const BackupSummary({
    required this.vaultUuid,
    required this.fileCount,
    required this.objectCount,
    required this.totalBytes,
    required this.createdAt,
  });

  final String vaultUuid;
  final int fileCount;
  final int objectCount;
  final int totalBytes;
  final DateTime createdAt;
}
