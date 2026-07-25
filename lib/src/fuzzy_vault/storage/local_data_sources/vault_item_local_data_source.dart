import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/vault_item_type.dart';
import '../storage_models/stored_vault_item.dart';

class VaultItemLocalDataSource {
  VaultItemLocalDataSource({this.isar});
  final Isar? isar;
  SharedPreferences? _webPrefs;
  static const String _webKey = 'vault_items';

  Future<void> _initWeb() async {
    _webPrefs ??= await SharedPreferences.getInstance();
  }

  List<StoredVaultItem> _getWebItems() {
    if (_webPrefs == null) return [];
    final jsonString = _webPrefs!.getString(_webKey);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((e) => _itemFromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error loading vault items: $e');
      return [];
    }
  }

  Future<void> _saveWebItems(List<StoredVaultItem> items) async {
    if (_webPrefs == null) return;
    final jsonList = items.map(_itemToJson).toList();
    await _webPrefs!.setString(_webKey, jsonEncode(jsonList));
  }

  Future<void> saveItem(StoredVaultItem item) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      item.id = items.isEmpty ? 1 : items.map((i) => i.id).reduce((a, b) => a > b ? a : b) + 1;
      final index = items.indexWhere((i) => i.itemId == item.itemId);
      if (index >= 0) {
        items[index] = item;
      } else {
        items.add(item);
      }
      await _saveWebItems(items);
      return;
    }
    if (isar == null) return;
    await isar!.writeTxn(() async {
      await isar!.storedVaultItems.put(item);
    });
  }

  Future<StoredVaultItem?> getItem(String itemId) async {
    if (kIsWeb) {
      await _initWeb();
      try {
        return _getWebItems().firstWhere((i) => i.itemId == itemId);
      } catch (e) {
        return null;
      }
    }
    if (isar == null) return null;
    return isar!.storedVaultItems.filter().itemIdEqualTo(itemId).findFirst();
  }

  Future<List<StoredVaultItem>> getAllItems() async {
    if (kIsWeb) {
      await _initWeb();
      return _getWebItems();
    }
    if (isar == null) return [];
    return isar!.storedVaultItems.where().findAll();
  }

  Future<List<StoredVaultItem>> getItemsByGroup(String groupId) async {
    if (kIsWeb) {
      await _initWeb();
      return _getWebItems().where((i) => i.groupId == groupId).toList();
    }
    if (isar == null) return [];
    return isar!.storedVaultItems.filter().groupIdEqualTo(groupId).findAll();
  }

  Future<void> deleteItem(String itemId) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      items.removeWhere((i) => i.itemId == itemId);
      await _saveWebItems(items);
      return;
    }
    if (isar == null) return;
    await isar!.writeTxn(() async {
      await isar!.storedVaultItems.filter().itemIdEqualTo(itemId).deleteAll();
    });
  }

  Map<String, dynamic> _itemToJson(StoredVaultItem item) {
    return {
      'id': item.id,
      'itemId': item.itemId,
      'title': item.title,
      'groupId': item.groupId,
      'type': item.type.index,
      'tags': item.tags,
      'isFavorite': item.isFavorite,
      'hasCustomPassword': item.hasCustomPassword,
      'createdAt': item.createdAt.toIso8601String(),
      'updatedAt': item.updatedAt.toIso8601String(),
      'contentVersion': item.contentVersion,
    };
  }

  StoredVaultItem _itemFromJson(Map<String, dynamic> json) {
    return StoredVaultItem()
      ..id = json['id'] as int? ?? 0
      ..itemId = json['itemId'] as String? ?? ''
      ..title = json['title'] as String? ?? ''
      ..groupId = json['groupId'] as String? ?? ''
      ..type = VaultItemType.values[json['type'] as int? ?? 0]
      ..tags = (json['tags'] as List<dynamic>?)?.cast<String>() ?? []
      ..isFavorite = json['isFavorite'] as bool? ?? false
      ..hasCustomPassword = json['hasCustomPassword'] as bool? ?? false
      ..createdAt = DateTime.parse(json['createdAt'] as String)
      ..updatedAt = DateTime.parse(json['updatedAt'] as String)
      ..contentVersion = json['contentVersion'] as int? ?? 1;
  }
}
