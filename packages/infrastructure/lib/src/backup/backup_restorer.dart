import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../format/backup_manifest.dart';
import '../format/object_id.dart';
import '../storage/atomic_file_writer.dart';
import 'backup_hashing.dart';
import 'backup_opener.dart';
import 'backup_verifier.dart';

const _streamChunk = 64 * 1024;

/// Transactional restore of a backup container into a fresh (or explicitly
/// replaced) Vault directory. The target is only mutated after the backup has
/// been fully verified and every file extracted and re-verified; on any
/// failure the target is left untouched.
final class BackupRestorer {
  BackupRestorer({
    required SodiumSumo sodium,
    required DirectoryDurability durability,
    Random? random,
  }) : _sodium = sodium,
       _durability = durability,
       _random = random ?? Random.secure();

  final SodiumSumo _sodium;
  final DirectoryDurability _durability;
  final Random _random;

  Future<void> restore({
    required String backupPath,
    required Int8List passwordBytes,
    required String targetPath,
    required bool replaceExisting,
  }) async {
    // 1. Full isolated verification before touching the target.
    final report = await BackupVerifier(
      _sodium,
    ).verify(backupPath: backupPath, passwordBytes: passwordBytes);
    switch (report.status) {
      case BackupVerificationStatus.ok:
        break;
      case BackupVerificationStatus.wrongPassword:
        throw const VaultAuthenticationFailure();
      case BackupVerificationStatus.tampered:
      case BackupVerificationStatus.corrupt:
        throw const CorruptVaultDataFailure();
      case BackupVerificationStatus.unsupported:
        throw const UnsupportedVaultFormatFailure();
    }

    final file = File(backupPath);
    final handle = await file.open();
    try {
      final opened = await BackupOpener(
        _sodium,
      ).open(handle: handle, passwordBytes: passwordBytes);

      final target = Directory(targetPath);
      final targetExists = await target.exists();
      final targetEmpty = !targetExists || await target.list().isEmpty;
      if (targetExists && !targetEmpty && !replaceExisting) {
        throw const BackupTargetOccupied();
      }
      final parent = target.parent;
      if (!await parent.exists()) {
        throw FileSystemException('Target parent does not exist', parent.path);
      }

      final staging = Directory('${target.path}.restoring-${_randomSuffix()}');
      try {
        await staging.create();
        await _durability.syncDirectory(parent);
        await _extract(handle, opened, staging);
        await _verifyStaged(staging, opened.manifest);
        await _swap(staging, target);
      } catch (_) {
        if (await staging.exists()) {
          await staging.delete(recursive: true);
          await _durability.syncDirectory(parent);
        }
        rethrow;
      }
    } finally {
      await handle.close();
    }
  }

  Future<void> _extract(
    RandomAccessFile source,
    OpenedBackup opened,
    Directory staging,
  ) async {
    final separator = Platform.pathSeparator;
    source.setPosition(opened.filesStartOffset);
    for (final entry in opened.manifest.files) {
      final relative = entry.path.replaceAll('/', separator);
      final digest = await _writeStagedFile(
        '${staging.path}$separator$relative',
        source,
        entry.size,
      );
      final expected = _digestBytes(entry.digest);
      if (expected == null || !_bytesEqual(digest, expected)) {
        throw const CorruptVaultDataFailure();
      }
      if (entry.path.startsWith('objects/')) {
        final objectId = entry.path.substring(entry.path.length - 52);
        if (!_bytesEqual(digest, objectIdDigest(objectId))) {
          throw const CorruptVaultDataFailure();
        }
      }
    }
    // The derived index is not carried; recreate its empty home directory.
    final local = Directory('${staging.path}$separator${'local'}');
    await local.create();
    await _durability.syncDirectory(staging);
  }

  Future<Uint8List> _writeStagedFile(
    String targetPath,
    RandomAccessFile source,
    int size,
  ) async {
    final file = File(targetPath);
    final parent = file.parent;
    await parent.create(recursive: true);
    final temporary = File('$targetPath.tmp');
    final hasher = StreamingSha256();
    var remaining = size;
    final output = await temporary.open(mode: FileMode.write);
    try {
      while (remaining > 0) {
        final chunk = await source.read(
          remaining < _streamChunk ? remaining : _streamChunk,
        );
        if (chunk.isEmpty) throw const CorruptVaultDataFailure();
        hasher.add(chunk);
        await output.writeFrom(chunk);
        remaining -= chunk.length;
      }
      await output.flush();
    } finally {
      await output.close();
    }
    await _durability.syncDirectory(parent);
    await temporary.rename(targetPath);
    await _durability.syncDirectory(parent);
    return hasher.close();
  }

  Future<void> _verifyStaged(Directory staging, BackupManifest manifest) async {
    final separator = Platform.pathSeparator;
    for (final entry in manifest.files) {
      final path =
          '${staging.path}$separator${entry.path.replaceAll('/', separator)}';
      final file = File(path);
      if (!await file.exists() || await file.length() != entry.size) {
        throw const CorruptVaultDataFailure();
      }
      final digest = await sha256.bind(file.openRead()).first;
      final bytes = Uint8List.fromList(digest.bytes);
      final expected = _digestBytes(entry.digest);
      if (expected == null || !_bytesEqual(bytes, expected)) {
        throw const CorruptVaultDataFailure();
      }
      if (entry.path.startsWith('objects/')) {
        final objectId = entry.path.substring(entry.path.length - 52);
        if (!_bytesEqual(bytes, objectIdDigest(objectId))) {
          throw const CorruptVaultDataFailure();
        }
      }
    }
  }

  Future<void> _swap(Directory staging, Directory target) async {
    final parent = target.parent;
    if (await target.exists()) {
      final replaced = Directory('${target.path}.replaced-${_randomSuffix()}');
      await target.rename(replaced.path);
      await _durability.syncDirectory(parent);
      try {
        await staging.rename(target.path);
        await _durability.syncDirectory(parent);
      } catch (_) {
        if (!await target.exists() && await replaced.exists()) {
          await replaced.rename(target.path);
          await _durability.syncDirectory(parent);
        }
        rethrow;
      }
      await replaced.delete(recursive: true);
      await _durability.syncDirectory(parent);
    } else {
      await staging.rename(target.path);
      await _durability.syncDirectory(parent);
    }
  }

  String _randomSuffix() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
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

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
