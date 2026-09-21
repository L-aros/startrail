import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../format/backup_manifest.dart';
import '../format/head.dart';
import '../format/object_id.dart';
import '../format/vault_header.dart';
import 'backup_hashing.dart';
import 'backup_opener.dart';

const _streamChunk = 64 * 1024;

final class _ReadResult {
  const _ReadResult(this.digest, this.bytes);

  final Uint8List digest;
  final Uint8List? bytes;
}

/// Read-only isolated verification of a backup container. Never reads or
/// writes any Vault; the outcome distinguishes a wrong password from a
/// tampered or corrupt backup without exposing internal details.
final class BackupVerifier {
  BackupVerifier(this._sodium);

  final SodiumSumo _sodium;
  final VaultHeadCodec _headCodec = const VaultHeadCodec();
  final VaultHeaderCodec _vaultHeaderCodec = const VaultHeaderCodec();

  Future<BackupVerificationReport> verify({
    required String backupPath,
    required Int8List passwordBytes,
  }) async {
    final file = File(backupPath);
    if (!await file.exists()) {
      return const BackupVerificationReport(
        status: BackupVerificationStatus.corrupt,
      );
    }
    final handle = await file.open();
    try {
      return await _verify(handle, passwordBytes);
    } finally {
      await handle.close();
    }
  }

  Future<BackupVerificationReport> _verify(
    RandomAccessFile handle,
    Int8List passwordBytes,
  ) async {
    BackupVerificationReport corrupt() => const BackupVerificationReport(
      status: BackupVerificationStatus.corrupt,
    );
    BackupVerificationReport tampered() => const BackupVerificationReport(
      status: BackupVerificationStatus.tampered,
    );

    try {
      final opened = await BackupOpener(
        _sodium,
      ).open(handle: handle, passwordBytes: passwordBytes);
      final manifest = opened.manifest;

      Uint8List? headBytes;
      Uint8List? vaultHeaderBytes;
      await handle.setPosition(opened.filesStartOffset);
      for (final entry in manifest.files) {
        final keep = entry.path == 'HEAD' || entry.path == 'vault.header';
        final result = await _readAndHash(handle, entry.size, keep);
        if (result == null) return corrupt();
        final expected = _digestBytes(entry.digest);
        if (expected == null || !_bytesEqual(result.digest, expected)) {
          return tampered();
        }
        if (entry.path.startsWith('objects/')) {
          final objectId = entry.path.substring(entry.path.length - 52);
          if (!_bytesEqual(result.digest, objectIdDigest(objectId))) {
            return tampered();
          }
        }
        if (entry.path == 'HEAD') headBytes = result.bytes;
        if (entry.path == 'vault.header') vaultHeaderBytes = result.bytes;
      }

      final trailing = await handle.read(1);
      if (trailing.isNotEmpty) return tampered();

      if (headBytes == null || vaultHeaderBytes == null) return corrupt();
      if (!_verifyHead(headBytes, manifest)) return tampered();
      final vaultHeader = _vaultHeaderCodec.decode(vaultHeaderBytes);
      if (vaultHeader.vaultUuid != opened.header.vaultUuid) return tampered();

      return BackupVerificationReport(
        status: BackupVerificationStatus.ok,
        vaultUuid: manifest.vaultUuid,
        fileCount: manifest.fileCount,
        objectCount: manifest.objectCount,
        totalBytes: manifest.totalBytes,
        rootDigest: _digestString(opened.manifestCiphertext),
      );
    } on VaultAuthenticationFailure {
      return const BackupVerificationReport(
        status: BackupVerificationStatus.wrongPassword,
      );
    } on UnsupportedVaultFormatFailure {
      return const BackupVerificationReport(
        status: BackupVerificationStatus.unsupported,
      );
    } on CorruptVaultDataFailure {
      return corrupt();
    } on SodiumException {
      return tampered();
    } on Object {
      return corrupt();
    }
  }

  bool _verifyHead(Uint8List headBytes, BackupManifest manifest) {
    final head = _headCodec.decode(headBytes);
    final manifestPath = 'manifests/${head.manifest.manifestId}';
    for (final entry in manifest.files) {
      if (entry.path == manifestPath) {
        return entry.digest == head.manifest.cipherDigest;
      }
    }
    return false;
  }

  Future<_ReadResult?> _readAndHash(
    RandomAccessFile handle,
    int size,
    bool keepBytes,
  ) async {
    final hasher = StreamingSha256();
    final builder = keepBytes ? BytesBuilder(copy: false) : null;
    var remaining = size;
    while (remaining > 0) {
      final chunk = await handle.read(
        remaining < _streamChunk ? remaining : _streamChunk,
      );
      if (chunk.isEmpty) return null;
      hasher.add(chunk);
      builder?.add(chunk);
      remaining -= chunk.length;
    }
    return _ReadResult(hasher.close(), builder?.takeBytes());
  }
}

Uint8List? _digestBytes(String digest) {
  if (!digest.startsWith('sha256:')) return null;
  final text = digest.substring(7);
  if (text.contains('=')) return null;
  final padding = '=' * ((4 - text.length % 4) % 4);
  final decoded = base64Url.decode('$text$padding');
  if (decoded.length != 32) return null;
  return Uint8List.fromList(decoded);
}

String _digestString(Uint8List bytes) =>
    'sha256:${base64Url.encode(bytes).replaceAll('=', '')}';

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
