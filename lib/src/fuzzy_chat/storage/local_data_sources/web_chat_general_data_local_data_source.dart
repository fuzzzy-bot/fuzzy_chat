import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/enums/chat_setup_status.dart';
import '../storage_models/storage_models.dart';

/// Web implementation of ChatGeneralDataLocalDataSource using SharedPreferences
class WebChatGeneralDataLocalDataSource {
  SharedPreferences? _prefs;

  Future<void> _init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  String get _key => 'web_chat_general_data';

  List<StoredChatGeneralData> get _items {
    if (_prefs == null) return [];
    final jsonString = _prefs!.getString(_key);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error loading chat general data: $e');
      return [];
    }
  }

  Future<void> _saveItems(List<StoredChatGeneralData> items) async {
    if (_prefs == null) return;
    final jsonList = items.map(_toJson).toList();
    await _prefs!.setString(_key, jsonEncode(jsonList));
  }

  Future<List<StoredChatGeneralData>> getAllChats() async {
    await _init();
    return _items;
  }

  Future<void> addChat(StoredChatGeneralData storedChatGeneralData) async {
    await _init();
    final items = _items;
    storedChatGeneralData.id = items.isEmpty ? 1 : items.map((i) => i.id).reduce((a, b) => a > b ? a : b) + 1;
    items.add(storedChatGeneralData);
    await _saveItems(items);
  }

  Future<StoredChatGeneralData?> getChatById(String chatId) async {
    await _init();
    try {
      return _items.firstWhere((i) => i.chatId == chatId);
    } catch (e) {
      return null;
    }
  }

  Future<StoredChatGeneralData?> getChatByName(String name) async {
    await _init();
    try {
      return _items.firstWhere((i) => i.chatName == name);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateChat(StoredChatGeneralData storedChatGeneralData) async {
    await _init();
    final items = _items;
    final index = items.indexWhere((i) => i.id == storedChatGeneralData.id);
    if (index >= 0) {
      items[index] = storedChatGeneralData;
    } else {
      items.add(storedChatGeneralData);
    }
    await _saveItems(items);
  }

  Future<void> deleteChat(String chatId) async {
    await _init();
    final items = _items;
    items.removeWhere((i) => i.chatId == chatId);
    await _saveItems(items);
  }

  Map<String, dynamic> _toJson(StoredChatGeneralData item) {
    return {
      'id': item.id,
      'chatId': item.chatId,
      'chatName': item.chatName,
      'setupStatus': item.setupStatus.index,
      'createdAt': item.createdAt.toIso8601String(),
      'didAcceptInvitation': item.didAcceptInvitation,
    };
  }

  StoredChatGeneralData _fromJson(Map<String, dynamic> json) {
    return StoredChatGeneralData()
      ..id = json['id'] as int? ?? 0
      ..chatId = json['chatId'] as String? ?? ''
      ..chatName = json['chatName'] as String? ?? ''
      ..setupStatus = ChatSetupStatus.values[json['setupStatus'] as int? ?? 0]
      ..createdAt = DateTime.parse(json['createdAt'] as String)
      ..didAcceptInvitation = json['didAcceptInvitation'] as bool? ?? false;
  }
}
