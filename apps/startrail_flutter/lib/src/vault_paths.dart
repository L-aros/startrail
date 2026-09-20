import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class VaultPaths {
  Future<String> defaultVaultPath();
  Future<String?> chooseCreationPath();
  Future<String?> chooseExistingVault();
}

final class PlatformVaultPaths implements VaultPaths {
  @override
  Future<String> defaultVaultPath() async {
    final support = await getApplicationSupportDirectory();
    return _join(support.path, 'vault');
  }

  @override
  Future<String?> chooseCreationPath() async {
    final parent = await getDirectoryPath(canCreateDirectories: true);
    return parent == null ? null : _join(parent, 'vault');
  }

  @override
  Future<String?> chooseExistingVault() =>
      getDirectoryPath(canCreateDirectories: false);

  String _join(String parent, String child) =>
      '$parent${Platform.pathSeparator}$child';
}
