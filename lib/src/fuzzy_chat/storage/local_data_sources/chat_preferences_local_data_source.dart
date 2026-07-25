import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage_models/storage_models.dart';

class ChatPreferencesLocalDataSource {
  final Isar isar;
  SharedPreferences? _webPrefs;
  static const String _webKey = 'chat_preferences';

  ChatPreferencesLocalDataSource(this.isar);

  Future<void> _initWeb() async {
    _webPrefs ??= await SharedPreferences.getInstance();
  }

  Future<StoredChatPreferences?> getChatPreferences() async {
    if (kIsWeb) {
      await _initWeb();
      final jsonString = _webPrefs!.getString(_webKey);
      if (jsonString == null || jsonString.isEmpty) return null;
      try {
        return _fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
      } catch (e) {
        return null;
      }
    }
    return await isar.storedChatPreferences.where().findFirst();
  }

  Future<void> saveChatPreferences(StoredChatPreferences preferences) async {
    if (kIsWeb) {
      await _initWeb();
      await _webPrefs!.setString(_webKey, jsonEncode(_toJson(preferences)));
      return;
    }
    await isar.writeTxn(() async {
      await isar.storedChatPreferences.put(preferences);
    });
  }

  Future<void> updateChatPreferences(StoredChatPreferences preferences) async {
    if (kIsWeb) {
      await _initWeb();
      await _webPrefs!.setString(_webKey, jsonEncode(_toJson(preferences)));
      return;
    }
    await isar.writeTxn(() async {
      await isar.storedChatPreferences.put(preferences);
    });
  }

  Map<String, dynamic> _toJson(StoredChatPreferences item) {
    return {
      'id': item.id,
      'theme': item.theme,
      'showTimestamps': item.showTimestamps,
      'lastUpdated': item.lastUpdated.toIso8601String(),
    };
  }

  StoredChatPreferences _fromJson(Map<String, dynamic> json) {
    return StoredChatPreferences()
      ..id = json['id'] as int? ?? 0
      ..theme = json['theme'] as String?
      ..showTimestamps = json['showTimestamps'] as bool? ?? true
      ..lastUpdated = DateTime.parse(json['lastUpdated'] as String);
  }
}
