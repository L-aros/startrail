import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:sodium/sodium_sumo.dart';

import '../storage/atomic_file_writer.dart';
import 'backup_creator.dart';
import 'backup_restorer.dart';
import 'backup_verifier.dart';

/// Infrastructure adapter implementing [BackupStore].
///
/// [createBackup] is bound to an unlocked Vault session (vault directory,
/// UUID and device id) and therefore requires those fields; [verifyBackup] and
/// [restoreBackup] are stateless and may be used with a sessionless instance.
final class VaultBackupStore implements BackupStore {
  VaultBackupStore({
    required SodiumSumo sodium,
    required DirectoryDurability durability,
    Directory? vault,
    Uint8List? vaultUuid,
    String? deviceId,
    Random? random,
    DateTime Function()? clock,
  }) : _sodium = sodium,
       _durability = durability,
       _vault = vault,
       _vaultUuid = vaultUuid == null ? null : Uint8List.fromList(vaultUuid),
       _deviceId = deviceId,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final SodiumSumo _sodium;
  final DirectoryDurability _durability;
  final Directory? _vault;
  final Uint8List? _vaultUuid;
  final String? _deviceId;
  final Random _random;
  final DateTime Function() _clock;

  @override
  Future<BackupSummary> createBackup({
    required String targetPath,
    required Int8List passwordBytes,
  }) {
    final vault = _vault;
    final vaultUuid = _vaultUuid;
    final deviceId = _deviceId;
    if (vault == null || vaultUuid == null || deviceId == null) {
      throw StateError('createBackup requires an unlocked Vault session');
    }
    return BackupCreator(
      sodium: _sodium,
      vault: vault,
      vaultUuid: vaultUuid,
      deviceId: deviceId,
      durability: _durability,
      random: _random,
      clock: _clock,
    ).createBackup(targetPath: targetPath, passwordBytes: passwordBytes);
  }

  @override
  Future<BackupVerificationReport> verifyBackup({
    required String backupPath,
    required Int8List passwordBytes,
  }) {
    return BackupVerifier(
      _sodium,
    ).verify(backupPath: backupPath, passwordBytes: passwordBytes);
  }

  @override
  Future<void> restoreBackup({
    required String backupPath,
    required Int8List passwordBytes,
    required String targetPath,
    required bool replaceExisting,
  }) {
    return BackupRestorer(
      sodium: _sodium,
      durability: _durability,
      random: _random,
    ).restore(
      backupPath: backupPath,
      passwordBytes: passwordBytes,
      targetPath: targetPath,
      replaceExisting: replaceExisting,
    );
  }
}
