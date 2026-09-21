import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../format/head.dart';
import '../format/manifest_codec.dart';
import '../format/vault_header.dart';
import '../storage/atomic_file_writer.dart';
import '../storage/index_database.dart';
import 'vault_entry_store.dart';
import 'vault_unlocker.dart';

/// An unlocked Vault with its derived SQLCipher index and entry store.
///
/// This is the single high-level entry point the application layer uses after
/// successful authentication; it owns all sensitive state and must be
/// [dispose]d when the session is locked.
final class VaultSession {
  VaultSession._(this.unlocked, this.index, this.entryStore);

  final UnlockedVault unlocked;
  final EncryptedIndexDatabase index;
  final VaultEntryStore entryStore;

  /// Unlocks [vault], verifies the manifest, opens (or rebuilds) the index and
  /// wires up the entry store. The current device id is taken from the manifest
  /// writer for this single-device milestone.
  static Future<VaultSession> open({
    required Directory vault,
    required Int8List passwordBytes,
    required DirectoryDurability durability,
    DateTime Function()? clock,
  }) async {
    final sodium = await SodiumSumoInit.init();
    final unlocker = await VaultUnlocker.initialize();
    final unlocked = await unlocker.unlock(
      vault: vault,
      passwordBytes: passwordBytes,
    );

    final separator = Platform.pathSeparator;
    final headBytes = await File('${vault.path}${separator}HEAD').readAsBytes();
    final head = const VaultHeadCodec().decode(headBytes);
    final manifest = const ManifestV1Codec().decode(unlocked.manifestPlaintext);

    final indexFactory = IndexDatabaseFactory(sodium, durability: durability);
    final index = await indexFactory.openOrRebuild(
      '${vault.path}${separator}local${separator}index.db',
      masterKey: unlocked.masterKey,
      manifestId: head.manifest.manifestId,
      populate: (_) {
        // Index reconstruction from authenticated objects lands in Milestone 3.
      },
    );

    final entryStore = VaultEntryStore(
      sodium: sodium,
      vault: vault,
      vaultUuid: uuidBytes(unlocked.vaultUuid),
      masterKey: unlocked.masterKey,
      deviceId: manifest.writerDeviceId,
      manifest: manifest,
      manifestId: head.manifest.manifestId,
      index: index,
      durability: durability,
      clock: clock,
    );

    return VaultSession._(unlocked, index, entryStore);
  }

  void dispose() {
    entryStore.dispose();
    index.close();
    unlocked.dispose();
  }
}
