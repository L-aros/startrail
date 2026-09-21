import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';

import 'canonical_json.dart';
import 'entry_object.dart';
import 'vault_header.dart';

/// One authoritative Vault file recorded in the backup manifest, with its
/// exact size and `sha256:<base64url>` digest.
final class BackupFileEntry {
  const BackupFileEntry({
    required this.path,
    required this.size,
    required this.digest,
  });

  final String path;
  final int size;
  final String digest;
}

/// The encrypted manifest describing every file carried by a backup container.
final class BackupManifest {
  BackupManifest({
    required this.vaultUuid,
    required this.createdAt,
    required this.deviceId,
    required List<BackupFileEntry> files,
  }) : files = List.unmodifiable(files);

  final String vaultUuid;
  final DateTime createdAt;
  final String deviceId;
  final List<BackupFileEntry> files;

  int get fileCount => files.length;

  int get objectCount =>
      files.where((file) => file.path.startsWith('objects/')).length;

  int get totalBytes => files.fold(0, (sum, file) => sum + file.size);
}

final class BackupManifestCodec {
  const BackupManifestCodec();

  Uint8List encode(BackupManifest manifest) {
    uuidBytes(manifest.vaultUuid);
    uuid(manifest.deviceId);
    for (final file in manifest.files) {
      _validatePath(file.path);
      _validateDigest(file.digest);
    }
    return encodeCanonicalJson({
      'created_at': formatTimestamp(manifest.createdAt),
      'device_id': manifest.deviceId,
      'files': [
        for (final file in manifest.files)
          {'digest': file.digest, 'path': file.path, 'size': file.size},
      ],
      'format': 1,
      'vault_uuid': manifest.vaultUuid,
    });
  }

  BackupManifest decode(Uint8List plaintext) {
    try {
      final decoded = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (!_bytesEqual(plaintext, encodeCanonicalJson(decoded))) {
        throw const CorruptVaultDataFailure();
      }
      _expectKeys(decoded, const {
        'created_at',
        'device_id',
        'files',
        'format',
        'vault_uuid',
      });
      if (decoded['format'] != 1) {
        throw const UnsupportedVaultFormatFailure();
      }
      final vaultUuid = decoded['vault_uuid'];
      final deviceId = decoded['device_id'];
      if (vaultUuid is! String || deviceId is! String) {
        throw const FormatException();
      }
      uuidBytes(vaultUuid);
      uuid(deviceId);
      final files = <BackupFileEntry>[];
      final rawFiles = decoded['files'];
      if (rawFiles is! List) throw const FormatException();
      for (final raw in rawFiles) {
        if (raw is! Map<String, dynamic>) throw const FormatException();
        _expectKeys(raw, const {'digest', 'path', 'size'});
        final path = raw['path'];
        final size = raw['size'];
        final digest = raw['digest'];
        if (path is! String || size is! int || size < 0 || digest is! String) {
          throw const FormatException();
        }
        _validatePath(path);
        _validateDigest(digest);
        files.add(BackupFileEntry(path: path, size: size, digest: digest));
      }
      return BackupManifest(
        vaultUuid: vaultUuid,
        createdAt: parseTimestamp(decoded['created_at'] as String),
        deviceId: deviceId,
        files: files,
      );
    } on VaultFailure {
      rethrow;
    } on Object {
      throw const CorruptVaultDataFailure();
    }
  }
}

final _objectPath = RegExp(r'^objects/[a-z2-7]{2}/[a-z2-7]{52}$');
final _manifestPath = RegExp(r'^manifests/[a-z2-7]{52}$');
final _digest = RegExp(r'^sha256:[A-Za-z0-9_-]{43}$');

/// Only the four authoritative file kinds are permitted; any other path (for
/// example a path traversal) is rejected.
void _validatePath(String path) {
  final allowed =
      path == 'vault.header' ||
      path == 'HEAD' ||
      _objectPath.hasMatch(path) ||
      _manifestPath.hasMatch(path);
  if (!allowed) throw const FormatException('invalid backup file path');
}

void _validateDigest(String digest) {
  if (!_digest.hasMatch(digest)) throw const FormatException('invalid digest');
}

void _expectKeys(Map<String, dynamic> value, Set<String> keys) {
  if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
    throw const UnsupportedVaultFormatFailure();
  }
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
