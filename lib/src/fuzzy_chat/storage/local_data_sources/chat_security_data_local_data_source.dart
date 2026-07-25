import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage_models/storage_models.dart';

class ChatSecurityDataLocalDataSource {
  final Isar isar;
  SharedPreferences? _webPrefs;
  static const String _webKey = 'chat_security_data';

  ChatSecurityDataLocalDataSource(this.isar);

  Future<void> _initWeb() async {
    _webPrefs ??= await SharedPreferences.getInstance();
  }

  Future<void> addSecurityData(StoredChatSecurityData securityData) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      securityData.id = items.isEmpty ? 1 : items.map((i) => i.id).reduce((a, b) => a > b ? a : b) + 1;
      final index = items.indexWhere((i) => i.chatId == securityData.chatId);
      if (index >= 0) {
        items[index] = securityData;
      } else {
        items.add(securityData);
      }
      await _saveWebItems(items);
      return;
    }
    await isar.writeTxn(() async {
      await isar.storedChatSecurityDatas.put(securityData);
    });
  }

  Future<StoredChatSecurityData?> getSecurityDataForChat(String chatId) async {
    if (kIsWeb) {
      await _initWeb();
      try {
        return _getWebItems().firstWhere((i) => i.chatId == chatId);
      } catch (e) {
        return null;
      }
    }
    return await isar.storedChatSecurityDatas
        .filter()
        .chatIdEqualTo(chatId)
        .findFirst();
  }

  Future<void> updateSecurityData(StoredChatSecurityData securityData) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      final index = items.indexWhere((i) => i.id == securityData.id);
      if (index >= 0) {
        items[index] = securityData;
      } else {
        items.add(securityData);
      }
      await _saveWebItems(items);
      return;
    }
    await isar.writeTxn(() async {
      await isar.storedChatSecurityDatas.put(securityData);
    });
  }

  Future<void> deleteSecurityData(String chatId) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      items.removeWhere((i) => i.chatId == chatId);
      await _saveWebItems(items);
      return;
    }
    final securityData = await getSecurityDataForChat(chatId);
    if (securityData != null) {
      await isar.writeTxn(() async {
        await isar.storedChatSecurityDatas.delete(securityData.id);
      });
    }
  }

  List<StoredChatSecurityData> _getWebItems() {
    if (_webPrefs == null) return [];
    final jsonString = _webPrefs!.getString(_webKey);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error loading chat security data: $e');
      return [];
    }
  }

  Future<void> _saveWebItems(List<StoredChatSecurityData> items) async {
    if (_webPrefs == null) return;
    final jsonList = items.map(_toJson).toList();
    await _webPrefs!.setString(_webKey, jsonEncode(jsonList));
  }

  Map<String, dynamic> _toJson(StoredChatSecurityData item) {
    return {
      'id': item.id,
      'chatId': item.chatId,
      'invitationFilePath': item.invitationFilePath,
      'acceptanceFilePath': item.acceptanceFilePath,
      'encryptedSymmetricKey': item.encryptedSymmetricKey,
      'createdAt': item.createdAt.toIso8601String(),
    };
  }

  StoredChatSecurityData _fromJson(Map<String, dynamic> json) {
    return StoredChatSecurityData()
      ..id = json['id'] as int? ?? 0
      ..chatId = json['chatId'] as String? ?? ''
      ..invitationFilePath = json['invitationFilePath'] as String?
      ..acceptanceFilePath = json['acceptanceFilePath'] as String?
      ..encryptedSymmetricKey = json['encryptedSymmetricKey'] as String?
      ..createdAt = DateTime.parse(json['createdAt'] as String);
  }
}
