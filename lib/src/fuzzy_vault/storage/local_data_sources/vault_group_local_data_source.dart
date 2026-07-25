import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage_models/stored_vault_group.dart';

class VaultGroupLocalDataSource {
  VaultGroupLocalDataSource({this.isar});
  final Isar? isar;
  SharedPreferences? _webPrefs;
  static const String _webKey = 'vault_groups';

  Future<void> _initWeb() async {
    _webPrefs ??= await SharedPreferences.getInstance();
  }

  List<StoredVaultGroup> _getWebItems() {
    if (_webPrefs == null) return [];
    final jsonString = _webPrefs!.getString(_webKey);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((e) => _groupFromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error loading vault groups: $e');
      return [];
    }
  }

  Future<void> _saveWebItems(List<StoredVaultGroup> items) async {
    if (_webPrefs == null) return;
    final jsonList = items.map(_groupToJson).toList();
    await _webPrefs!.setString(_webKey, jsonEncode(jsonList));
  }

  Future<void> saveGroup(StoredVaultGroup group) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      group.id = items.isEmpty ? 1 : items.map((i) => i.id).reduce((a, b) => a > b ? a : b) + 1;
      final index = items.indexWhere((i) => i.groupId == group.groupId);
      if (index >= 0) {
        items[index] = group;
      } else {
        items.add(group);
      }
      await _saveWebItems(items);
      return;
    }
    if (isar == null) return;
    await isar!.writeTxn(() async {
      await isar!.storedVaultGroups.put(group);
    });
  }

  Future<StoredVaultGroup?> getGroup(String groupId) async {
    if (kIsWeb) {
      await _initWeb();
      try {
        return _getWebItems().firstWhere((i) => i.groupId == groupId);
      } catch (e) {
        return null;
      }
    }
    if (isar == null) return null;
    return isar!.storedVaultGroups.filter().groupIdEqualTo(groupId).findFirst();
  }

  Future<List<StoredVaultGroup>> getAllGroups() async {
    if (kIsWeb) {
      await _initWeb();
      return _getWebItems();
    }
    if (isar == null) return [];
    return isar!.storedVaultGroups.where().findAll();
  }

  Future<void> deleteGroup(String groupId) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      items.removeWhere((i) => i.groupId == groupId);
      await _saveWebItems(items);
      return;
    }
    if (isar == null) return;
    await isar!.writeTxn(() async {
      await isar!.storedVaultGroups.filter().groupIdEqualTo(groupId).deleteAll();
    });
  }

  Map<String, dynamic> _groupToJson(StoredVaultGroup item) {
    return {
      'id': item.id,
      'groupId': item.groupId,
      'name': item.name,
      'emoji': item.emoji,
      'colorIndex': item.colorIndex,
      'sortOrder': item.sortOrder,
      'hasCustomPassword': item.hasCustomPassword,
      'createdAt': item.createdAt.toIso8601String(),
      'updatedAt': item.updatedAt.toIso8601String(),
    };
  }

  StoredVaultGroup _groupFromJson(Map<String, dynamic> json) {
    return StoredVaultGroup()
      ..id = json['id'] as int? ?? 0
      ..groupId = json['groupId'] as String? ?? ''
      ..name = json['name'] as String? ?? ''
      ..emoji = json['emoji'] as String? ?? ''
      ..colorIndex = json['colorIndex'] as int? ?? 0
      ..sortOrder = json['sortOrder'] as int? ?? 0
      ..hasCustomPassword = json['hasCustomPassword'] as bool? ?? false
      ..createdAt = DateTime.parse(json['createdAt'] as String)
      ..updatedAt = DateTime.parse(json['updatedAt'] as String);
  }
}
