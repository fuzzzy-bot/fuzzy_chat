import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class VaultFileDataSource {
  VaultFileDataSource({required this.vaultDirectoryPath});
  final String vaultDirectoryPath;

  // Web storage using SharedPreferences for file content
  SharedPreferences? _webPrefs;
  static const String _webMetaKey = 'vault_meta';
  static const String _webItemsPrefix = 'vault_item_';

  Future<void> _initWeb() async {
    _webPrefs ??= await SharedPreferences.getInstance();
  }

  Directory get _vaultDir => Directory(vaultDirectoryPath);
  Directory get _itemsDir => Directory(path.join(vaultDirectoryPath, 'items'));
  Directory get _tmpDir => Directory(path.join(vaultDirectoryPath, '.tmp'));
  File get _metaFile => File(path.join(vaultDirectoryPath, 'vault.meta'));

  Directory get _stagingDir =>
      Directory(path.join(vaultDirectoryPath, '.staging'));
  Directory get _stagingItemsDir =>
      Directory(path.join(_stagingDir.path, 'items'));
  File get _stagingMetaFile => File(path.join(_stagingDir.path, 'vault.meta'));
  File get _stagingCommitMarker =>
      File(path.join(_stagingDir.path, '.committed'));

  Future<void> initDirectories() async {
    if (kIsWeb) return;
    if (!await _vaultDir.exists()) await _vaultDir.create(recursive: true);
    if (!await _itemsDir.exists()) await _itemsDir.create(recursive: true);
    if (!await _tmpDir.exists()) await _tmpDir.create(recursive: true);
  }

  Future<void> writeMetaAtomic(List<int> bytes) async {
    if (kIsWeb) {
      await _initWeb();
      await _webPrefs!.setString(_webMetaKey, base64Encode(bytes));
      return;
    }
    await initDirectories();
    final tmpFile = File(path.join(_tmpDir.path, 'vault.meta.tmp'));
    await tmpFile.writeAsBytes(bytes, flush: true);
    await tmpFile.rename(_metaFile.path);
  }

  Future<List<int>?> readMeta() async {
    if (kIsWeb) {
      await _initWeb();
      final base64String = _webPrefs!.getString(_webMetaKey);
      if (base64String == null || base64String.isEmpty) return null;
      return base64Decode(base64String);
    }
    if (!await _metaFile.exists()) return null;
    return await _metaFile.readAsBytes();
  }

  Future<void> writeItemAtomic(String itemId, List<int> bytes) async {
    if (kIsWeb) {
      await _initWeb();
      await _webPrefs!.setString('$_webItemsPrefix$itemId', base64Encode(bytes));
      return;
    }
    await initDirectories();
    final tmpFile = File(path.join(_tmpDir.path, '$itemId.vault.tmp'));
    await tmpFile.writeAsBytes(bytes, flush: true);
    final itemFile = File(path.join(_itemsDir.path, '$itemId.vault'));
    await tmpFile.rename(itemFile.path);
  }

  Future<List<int>?> readItem(String itemId) async {
    if (kIsWeb) {
      await _initWeb();
      final base64String = _webPrefs!.getString('$_webItemsPrefix$itemId');
      if (base64String == null || base64String.isEmpty) return null;
      return base64Decode(base64String);
    }
    final itemFile = File(path.join(_itemsDir.path, '$itemId.vault'));
    if (!await itemFile.exists()) return null;
    return await itemFile.readAsBytes();
  }

  Future<void> deleteItem(String itemId) async {
    if (kIsWeb) {
      await _initWeb();
      await _webPrefs!.remove('$_webItemsPrefix$itemId');
      return;
    }
    final itemFile = File(path.join(_itemsDir.path, '$itemId.vault'));
    if (await itemFile.exists()) {
      await itemFile.delete();
    }
  }

  Future<void> clearAll() async {
    if (kIsWeb) {
      await _initWeb();
      await _webPrefs!.remove(_webMetaKey);
      final keys = _webPrefs!.getKeys().where((k) => k.startsWith(_webItemsPrefix));
      for (final key in keys) {
        await _webPrefs!.remove(key);
      }
      return;
    }
    if (await _vaultDir.exists()) {
      await _vaultDir.delete(recursive: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Staged writes — used for atomic multi-file operations like password change.
  //
  // Flow:
  //   1. writeItemToStaging / writeMetaToStaging  → all data written to .staging/
  //   2. markStagingCommitted                     → marker file signals intent
  //   3. commitStagedPasswordChange               → renames staged → live
  //
  // Recovery (call on startup):
  //   - If .staging exists WITH .committed marker  → complete the commit
  //   - If .staging exists WITHOUT marker          → incomplete prep, rollback
  // ---------------------------------------------------------------------------

  Future<void> _initStagingDirectories() async {
    if (kIsWeb) return;
    if (!await _stagingDir.exists()) await _stagingDir.create(recursive: true);
    if (!await _stagingItemsDir.exists()) {
      await _stagingItemsDir.create(recursive: true);
    }
  }

  Future<void> writeItemToStaging(String itemId, List<int> bytes) async {
    if (kIsWeb) return;
    await _initStagingDirectories();
    final file = File(path.join(_stagingItemsDir.path, '$itemId.vault'));
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> writeMetaToStaging(List<int> bytes) async {
    if (kIsWeb) return;
    await _initStagingDirectories();
    await _stagingMetaFile.writeAsBytes(bytes, flush: true);
  }

  Future<void> markStagingCommitted() async {
    if (kIsWeb) return;
    await _stagingCommitMarker.writeAsString('committed', flush: true);
  }

  Future<void> commitStagedPasswordChange() async {
    if (kIsWeb) return;
    if (await _stagingItemsDir.exists()) {
      final stagedFiles = _stagingItemsDir.listSync().whereType<File>();
      for (final file in stagedFiles) {
        final dest = File(path.join(_itemsDir.path, path.basename(file.path)));
        await file.rename(dest.path);
      }
    }

    if (await _stagingMetaFile.exists()) {
      await _stagingMetaFile.rename(_metaFile.path);
    }

    await cleanupStaging();
  }

  Future<void> cleanupStaging() async {
    if (kIsWeb) return;
    if (await _stagingDir.exists()) {
      await _stagingDir.delete(recursive: true);
    }
  }

  /// Call on app startup. Recovers from an interrupted password change.
  ///
  /// - If the commit marker exists → the staging data is complete, finish the
  ///   commit (all items were re-encrypted and new metadata is ready).
  /// - If staging exists but no marker → data was still being prepared,
  ///   safe to discard (old items/metadata are still intact).
  Future<void> recoverStagedChangesIfNeeded() async {
    if (kIsWeb) return;
    if (!await _stagingDir.exists()) return;

    if (await _stagingCommitMarker.exists()) {
      await commitStagedPasswordChange();
    } else {
      await cleanupStaging();
    }
  }
}
