import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../crypto/password_kdf.dart';
import '../crypto/vault_key_wrapper.dart';
import '../crypto/vault_object_crypto.dart';
import '../format/head.dart';
import '../format/initial_manifest.dart';
import '../format/manifest_identity.dart';
import '../format/vault_header.dart';
import '../storage/atomic_file_writer.dart';

enum VaultCreationStage {
  headerWritten,
  manifestWritten,
  headWritten,
  verifiedBeforePublish,
}

typedef VaultCreationFaultInjector =
    Future<void> Function(VaultCreationStage stage);

final class CreatedVault {
  const CreatedVault({required this.vaultUuid, required this.deviceUuid});

  final String vaultUuid;
  final String deviceUuid;
}

final class VaultCreator {
  VaultCreator._({
    required SodiumSumo sodium,
    required DirectoryDurability durability,
    DateTime Function()? clock,
    VaultCreationFaultInjector? faultInjector,
    Random? random,
  }) : _sodium = sodium,
       _durability = durability,
       _clock = clock ?? DateTime.now,
       _faultInjector = faultInjector,
       _random = random ?? Random.secure();

  static Future<VaultCreator> initialize({
    required DirectoryDurability durability,
    DateTime Function()? clock,
    VaultCreationFaultInjector? faultInjector,
    Random? random,
  }) async => VaultCreator._(
    sodium: await SodiumSumoInit.init(),
    durability: durability,
    clock: clock,
    faultInjector: faultInjector,
    random: random,
  );

  final SodiumSumo _sodium;
  final DirectoryDurability _durability;
  final DateTime Function() _clock;
  final VaultCreationFaultInjector? _faultInjector;
  final Random _random;

  Future<CreatedVault> create({
    required Directory target,
    required Int8List passwordBytes,
  }) async {
    if (await target.exists()) {
      throw FileSystemException('Vault target already exists', target.path);
    }
    final parent = target.parent;
    if (!await parent.exists()) {
      throw FileSystemException('Vault parent does not exist', parent.path);
    }
    final staging = Directory('${target.path}.creating-${_randomHex(16)}');
    if (staging.parent.absolute.path != parent.absolute.path ||
        !staging.path.startsWith('${target.path}.creating-')) {
      throw StateError('Invalid staging path');
    }

    final vaultUuid = _uuidV4();
    final deviceUuid = _uuidV4();
    final salt = _sodium.randombytes.buf(argon2idSaltBytes);
    final kdf = PasswordKdf(_sodium);
    final kek = kdf.deriveKey(passwordBytes: passwordBytes, salt: salt);
    final objectCrypto = VaultObjectCrypto(_sodium);
    final masterKey = objectCrypto.generateMasterKey();

    try {
      await staging.create();
      await _durability.syncDirectory(parent);
      final objects = Directory(
        '${staging.path}${Platform.pathSeparator}objects',
      );
      final manifests = Directory(
        '${staging.path}${Platform.pathSeparator}manifests',
      );
      final local = Directory('${staging.path}${Platform.pathSeparator}local');
      await objects.create();
      await manifests.create();
      await local.create();
      await _durability.syncDirectory(staging);

      final writer = AtomicFileWriter(durability: _durability, random: _random);
      final wrapped = VaultKeyWrapper(
        _sodium,
      ).wrap(masterKey: masterKey, keyEncryptionKey: kek, vaultUuid: vaultUuid);
      final headerBytes = const VaultHeaderCodec().encode(
        VaultHeader(
          vaultUuid: vaultUuid,
          salt: salt,
          wrapNonce: wrapped.nonce,
          wrappedMasterKey: wrapped.ciphertext,
        ),
      );
      await writer.write(
        File('${staging.path}${Platform.pathSeparator}vault.header'),
        headerBytes,
      );
      await _inject(VaultCreationStage.headerWritten);

      final manifestPlaintext = encodeInitialManifest(
        writerDeviceId: deviceUuid,
        createdAt: _clock(),
      );
      final manifestCiphertext = objectCrypto.encrypt(
        plaintext: manifestPlaintext,
        masterKey: masterKey,
        vaultUuid: uuidBytes(vaultUuid),
        type: VaultObjectType.manifest,
        schemaVersion: 1,
      );
      final identity = ManifestIdentity.fromCiphertext(manifestCiphertext);
      await writer.write(
        File(
          '${manifests.path}${Platform.pathSeparator}${identity.manifestId}',
        ),
        manifestCiphertext,
      );
      await _inject(VaultCreationStage.manifestWritten);

      final headBytes = const VaultHeadCodec().encode(VaultHead(identity));
      await writer.write(
        File('${staging.path}${Platform.pathSeparator}HEAD'),
        headBytes,
      );
      await _inject(VaultCreationStage.headWritten);

      _verify(
        headerBytes: headerBytes,
        headBytes: headBytes,
        manifestCiphertext: manifestCiphertext,
        manifestPlaintext: manifestPlaintext,
        kek: kek,
      );
      await _inject(VaultCreationStage.verifiedBeforePublish);

      await staging.rename(target.path);
      await _durability.syncDirectory(parent);
      return CreatedVault(vaultUuid: vaultUuid, deviceUuid: deviceUuid);
    } catch (_) {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
        await _durability.syncDirectory(parent);
      }
      rethrow;
    } finally {
      masterKey.dispose();
      kek.dispose();
    }
  }

  void _verify({
    required Uint8List headerBytes,
    required Uint8List headBytes,
    required Uint8List manifestCiphertext,
    required Uint8List manifestPlaintext,
    required SecureKey kek,
  }) {
    final header = const VaultHeaderCodec().decode(headerBytes);
    final unwrapped = VaultKeyWrapper(_sodium).unwrap(
      ciphertext: header.wrappedMasterKey,
      nonce: header.wrapNonce,
      keyEncryptionKey: kek,
      vaultUuid: header.vaultUuid,
    );
    try {
      final head = const VaultHeadCodec().decode(headBytes);
      const VaultHeadCodec().verifyManifest(head, manifestCiphertext);
      final plaintext = VaultObjectCrypto(_sodium).decrypt(
        envelopeBytes: manifestCiphertext,
        masterKey: unwrapped,
        vaultUuid: uuidBytes(header.vaultUuid),
      );
      try {
        if (!_equal(plaintext, manifestPlaintext)) {
          throw StateError('Manifest mismatch');
        }
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }
    } finally {
      unwrapped.dispose();
    }
  }

  Future<void> _inject(VaultCreationStage stage) async {
    final injector = _faultInjector;
    if (injector != null) await injector(stage);
  }

  String _uuidV4() {
    final bytes = _sodium.randombytes.buf(16);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  String _randomHex(int count) => List.generate(
    count,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

bool _equal(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
