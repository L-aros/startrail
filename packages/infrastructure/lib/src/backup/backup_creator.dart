import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../crypto/password_kdf.dart';
import '../format/backup_header.dart';
import '../format/backup_manifest.dart';
import '../storage/atomic_file_writer.dart';
import 'backup_container.dart';
import 'backup_crypto.dart';

final class _SourceFile {
  const _SourceFile(this.relativePath, this.absolutePath);

  final String relativePath;
  final String absolutePath;
}

/// Produces a single-file authenticated backup container from an unlocked
/// Vault. Every authoritative file is carried byte-for-byte; the container
/// only adds integrity and a format envelope, so `object_id ==
/// base32lower(SHA-256(bytes))` remains directly verifiable.
final class BackupCreator {
  BackupCreator({
    required SodiumSumo sodium,
    required Directory vault,
    required Uint8List vaultUuid,
    required String deviceId,
    required DirectoryDurability durability,
    Random? random,
    DateTime Function()? clock,
  }) : _sodium = sodium,
       _vault = vault,
       _vaultUuidString = _uuidText(vaultUuid),
       _deviceId = deviceId,
       _durability = durability,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final SodiumSumo _sodium;
  final Directory _vault;
  final String _vaultUuidString;
  final String _deviceId;
  final DirectoryDurability _durability;
  final Random _random;
  final DateTime Function() _clock;
  final BackupHeaderCodec _headerCodec = const BackupHeaderCodec();
  final BackupManifestCodec _manifestCodec = const BackupManifestCodec();

  Future<BackupSummary> createBackup({
    required String targetPath,
    required Int8List passwordBytes,
  }) async {
    final files = _collectFiles();
    final entries = <BackupFileEntry>[];
    for (final file in files) {
      final size = File(file.absolutePath).lengthSync();
      final digestBytes = await _hashFile(file.absolutePath);
      entries.add(
        BackupFileEntry(
          path: file.relativePath,
          size: size,
          digest: _digestString(digestBytes),
        ),
      );
    }

    final manifest = BackupManifest(
      vaultUuid: _vaultUuidString,
      createdAt: _clock(),
      deviceId: _deviceId,
      files: entries,
    );
    final manifestBytes = _manifestCodec.encode(manifest);

    final crypto = BackupCrypto(_sodium);
    final salt = _sodium.randombytes.buf(argon2idSaltBytes);
    final backupKey = crypto.generateBackupKey();
    SecureKey? kek;
    try {
      kek = PasswordKdf(
        _sodium,
      ).deriveKey(passwordBytes: passwordBytes, salt: salt);
      final wrapped = crypto.wrapBackupKey(
        backupKey: backupKey,
        keyEncryptionKey: kek,
        vaultUuid: _vaultUuidString,
      );
      final headerBytes = _headerCodec.encode(
        BackupHeader(
          vaultUuid: _vaultUuidString,
          salt: salt,
          wrapNonce: wrapped.nonce,
          wrappedBackupKey: wrapped.ciphertext,
        ),
      );
      final sealed = crypto.sealManifest(
        plaintext: manifestBytes,
        backupKey: backupKey,
        vaultUuid: _vaultUuidString,
      );

      await _writeContainer(
        targetPath,
        headerBytes: headerBytes,
        manifestNonce: sealed.nonce,
        manifestCiphertext: sealed.ciphertext,
        files: files,
      );
    } finally {
      backupKey.dispose();
      kek?.dispose();
    }

    return BackupSummary(
      vaultUuid: _vaultUuidString,
      fileCount: manifest.fileCount,
      objectCount: manifest.objectCount,
      totalBytes: manifest.totalBytes,
      createdAt: manifest.createdAt,
    );
  }

  List<_SourceFile> _collectFiles() {
    final separator = Platform.pathSeparator;
    final root = _vault.path;
    final files = <_SourceFile>[];
    final header = File('$root${separator}vault.header');
    if (header.existsSync()) {
      files.add(const _SourceFile('vault.header', ''));
    }
    final head = File('$root${separator}HEAD');
    if (head.existsSync()) {
      files.add(const _SourceFile('HEAD', ''));
    }
    _collectDirectory(Directory('$root${separator}objects'), 'objects', files);
    _collectDirectory(
      Directory('$root${separator}manifests'),
      'manifests',
      files,
    );
    // Resolve absolute paths and order deterministically for byte-identical
    // containers across platforms.
    final resolved = <_SourceFile>[
      for (final file in files)
        _SourceFile(
          file.relativePath,
          '$root$separator${file.relativePath.replaceAll('/', separator)}',
        ),
    ]..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return resolved;
  }

  void _collectDirectory(
    Directory directory,
    String prefix,
    List<_SourceFile> output,
  ) {
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync()) {
      final name = _basename(entity.path);
      if (entity is File) {
        output.add(_SourceFile('$prefix/$name', ''));
      } else if (entity is Directory) {
        _collectDirectory(entity, '$prefix/$name', output);
      }
    }
  }

  Future<Uint8List> _hashFile(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return Uint8List.fromList(digest.bytes);
  }

  Future<void> _writeContainer(
    String targetPath, {
    required Uint8List headerBytes,
    required Uint8List manifestNonce,
    required Uint8List manifestCiphertext,
    required List<_SourceFile> files,
  }) async {
    final target = File(targetPath);
    final parent = target.parent;
    if (!await parent.exists()) {
      throw FileSystemException('Target directory does not exist', parent.path);
    }
    final temporary = File('$targetPath.tmp-${_randomSuffix()}');
    try {
      final handle = await temporary.open(mode: FileMode.write);
      try {
        await handle.writeFrom(headerBytes);
        await handle.writeFrom(manifestNonce);
        await handle.writeFrom(encodeUint64Be(manifestCiphertext.length));
        await handle.writeFrom(manifestCiphertext);
        for (final file in files) {
          await _streamInto(handle, file.absolutePath);
        }
        await handle.flush();
      } finally {
        await handle.close();
      }
      await _durability.syncDirectory(parent);
      if (await target.exists()) {
        await target.delete();
      }
      await temporary.rename(targetPath);
      await _durability.syncDirectory(parent);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> _streamInto(RandomAccessFile handle, String path) async {
    final input = File(path).openRead();
    await for (final chunk in input) {
      await handle.writeFrom(chunk);
    }
  }

  String _randomSuffix() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String _digestString(Uint8List digestBytes) =>
    'sha256:${base64Url.encode(digestBytes).replaceAll('=', '')}';

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

String _uuidText(Uint8List bytes) {
  if (bytes.length != 16) {
    throw ArgumentError.value(bytes.length, 'vaultUuid.length');
  }
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
