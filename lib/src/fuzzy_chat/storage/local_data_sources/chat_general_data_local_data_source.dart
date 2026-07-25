import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/models.dart';
import '../storage_models/storage_models.dart';

class ChatGeneralDataLocalDataSource {
  final Isar? isar;
  SharedPreferences? _webPrefs;
  static const String _webKey = 'chat_general_data';

  ChatGeneralDataLocalDataSource({this.isar});

  Future<void> _initWeb() async {
    _webPrefs ??= await SharedPreferences.getInstance();
  }

  List<StoredChatGeneralData> _getWebItems() {
    if (_webPrefs == null) return [];
    final jsonString = _webPrefs!.getString(_webKey);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((e) => _chatFromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error loading chat general data: $e');
      return [];
    }
  }

  Future<void> _saveWebItems(List<StoredChatGeneralData> items) async {
    if (_webPrefs == null) return;
    final jsonList = items.map(_chatToJson).toList();
    await _webPrefs!.setString(_webKey, jsonEncode(jsonList));
  }

  Future<List<StoredChatGeneralData>> getAllChats() async {
    if (kIsWeb) {
      await _initWeb();
      return _getWebItems();
    }
    if (isar == null) return [];
    return await isar!.storedChatGeneralDatas.where().findAll();
  }

  Future<void> addChat(StoredChatGeneralData storedChatGeneralData) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      storedChatGeneralData.id = items.isEmpty ? 1 : items.map((i) => i.id).reduce((a, b) => a > b ? a : b) + 1;
      items.add(storedChatGeneralData);
      await _saveWebItems(items);
      return;
    }
    if (isar == null) return;
    await isar!.writeTxn(() async {
      await isar!.storedChatGeneralDatas.put(storedChatGeneralData);
    });
  }

  Future<StoredChatGeneralData?> getChatById(String chatId) async {
    if (kIsWeb) {
      await _initWeb();
      try {
        return _getWebItems().firstWhere((i) => i.chatId == chatId);
      } catch (e) {
        return null;
      }
    }
    if (isar == null) return null;
    return await isar!.storedChatGeneralDatas
        .filter()
        .chatIdEqualTo(chatId)
        .findFirst();
  }

  Future<StoredChatGeneralData?> getChatByName(String name) async {
    if (kIsWeb) {
      await _initWeb();
      try {
        return _getWebItems().firstWhere((i) => i.chatName == name);
      } catch (e) {
        return null;
      }
    }
    if (isar == null) return null;
    return await isar!.storedChatGeneralDatas
        .filter()
        .chatNameEqualTo(name)
        .findFirst();
  }

  Future<void> updateChat(StoredChatGeneralData storedChatGeneralData) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      final index = items.indexWhere((i) => i.id == storedChatGeneralData.id);
      if (index >= 0) {
        items[index] = storedChatGeneralData;
      } else {
        items.add(storedChatGeneralData);
      }
      await _saveWebItems(items);
      return;
    }
    if (isar == null) return;
    await isar!.writeTxn(() async {
      await isar!.storedChatGeneralDatas.put(storedChatGeneralData);
    });
  }

  Future<void> deleteChat(String chatId) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      items.removeWhere((i) => i.chatId == chatId);
      await _saveWebItems(items);
      return;
    }
    if (isar == null) return;
    final storedChatGeneralData = await getChatById(chatId);
    if (storedChatGeneralData != null) {
      await isar!.writeTxn(() async {
        await isar!.storedChatGeneralDatas.delete(storedChatGeneralData.id);
      });
    }
  }

  Map<String, dynamic> _chatToJson(StoredChatGeneralData item) {
    return {
      'id': item.id,
      'chatId': item.chatId,
      'chatName': item.chatName,
      'setupStatus': item.setupStatus.index,
      'createdAt': item.createdAt.toIso8601String(),
      'didAcceptInvitation': item.didAcceptInvitation,
    };
  }

  StoredChatGeneralData _chatFromJson(Map<String, dynamic> json) {
    return StoredChatGeneralData()
      ..id = json['id'] as int? ?? 0
      ..chatId = json['chatId'] as String? ?? ''
      ..chatName = json['chatName'] as String? ?? ''
      ..setupStatus = ChatSetupStatus.values[json['setupStatus'] as int? ?? 0]
      ..createdAt = DateTime.parse(json['createdAt'] as String)
      ..didAcceptInvitation = json['didAcceptInvitation'] as bool? ?? false;
  }
}
