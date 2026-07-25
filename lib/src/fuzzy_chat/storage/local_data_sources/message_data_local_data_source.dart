import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:fuzzy_chat/lib.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MessageDataLocalDataSource {
  final Isar? isar;
  SharedPreferences? _webPrefs;
  static const String _webKey = 'message_data';

  MessageDataLocalDataSource({this.isar});

  Future<void> _initWeb() async {
    _webPrefs ??= await SharedPreferences.getInstance();
  }

  List<StoredMessageData> _getWebItems() {
    if (_webPrefs == null) return [];
    final jsonString = _webPrefs!.getString(_webKey);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((e) => _messageFromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error loading message data: $e');
      return [];
    }
  }

  Future<void> _saveWebItems(List<StoredMessageData> items) async {
    if (_webPrefs == null) return;
    final jsonList = items.map(_messageToJson).toList();
    await _webPrefs!.setString(_webKey, jsonEncode(jsonList));
  }

  Future<int> addMessage(StoredMessageData messageData) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      messageData.id = items.isEmpty ? 1 : items.map((i) => i.id).reduce((a, b) => a > b ? a : b) + 1;
      items.add(messageData);
      await _saveWebItems(items);
      return messageData.id;
    }
    if (isar == null) return 0;
    return await isar!.writeTxn<int>(() async {
      return await isar!.storedMessageDatas.put(messageData);
    });
  }

  Future<List<StoredMessageData>> getMessagesForChat(String chatId) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems().where((i) => i.chatId == chatId).toList();
      items.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      return items;
    }
    if (isar == null) return [];
    return await isar!.storedMessageDatas
        .filter()
        .chatIdEqualTo(chatId)
        .sortBySentAt()
        .findAll();
  }

  Future<List<StoredMessageData>> getMessagesForChatPaginated(
    String chatId, {
    required int pageSize,
    required int pageIndex,
  }) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems().where((i) => i.chatId == chatId).toList();
      items.sort((a, b) => b.sentAt.compareTo(a.sentAt));
      final offset = pageIndex * pageSize;
      if (offset >= items.length) return [];
      return items.skip(offset).take(pageSize).toList();
    }
    if (isar == null) return [];
    final offset = pageIndex * pageSize;
    return await isar!.storedMessageDatas
        .filter()
        .chatIdEqualTo(chatId)
        .sortBySentAtDesc()
        .offset(offset)
        .limit(pageSize)
        .findAll();
  }

  Future<int> updateMessage(StoredMessageData messageData) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      final index = items.indexWhere((i) => i.id == messageData.id);
      if (index >= 0) {
        items[index] = messageData;
      } else {
        items.add(messageData);
      }
      await _saveWebItems(items);
      return messageData.id;
    }
    if (isar == null) return 0;
    return await isar!.writeTxn<int>(() async {
      return await isar!.storedMessageDatas.put(messageData);
    });
  }

  Future<void> deleteMessage(int messageId) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      items.removeWhere((i) => i.id == messageId);
      await _saveWebItems(items);
      return;
    }
    if (isar == null) return;
    await isar!.writeTxn(() async {
      await isar!.storedMessageDatas.delete(messageId);
    });
  }

  Future<void> deleteAllMessagesForChat(String chatId) async {
    if (kIsWeb) {
      await _initWeb();
      final items = _getWebItems();
      items.removeWhere((i) => i.chatId == chatId);
      await _saveWebItems(items);
      return;
    }
    if (isar == null) return;
    final messages = await getMessagesForChat(chatId);
    await isar!.writeTxn(() async {
      for (final message in messages) {
        await isar!.storedMessageDatas.delete(message.id);
      }
    });
  }

  Map<String, dynamic> _messageToJson(StoredMessageData item) {
    return {
      'id': item.id,
      'chatId': item.chatId,
      'encryptedMessage': item.encryptedMessage,
      'messageType': item.messageType,
      'sentAt': item.sentAt.toIso8601String(),
      'isSent': item.isSent,
    };
  }

  StoredMessageData _messageFromJson(Map<String, dynamic> json) {
    return StoredMessageData()
      ..id = json['id'] as int? ?? 0
      ..chatId = json['chatId'] as String? ?? ''
      ..encryptedMessage = json['encryptedMessage'] as String? ?? ''
      ..messageType = json['messageType'] as String? ?? MessageType.text.name
      ..sentAt = DateTime.parse(json['sentAt'] as String)
      ..isSent = json['isSent'] as bool? ?? false;
  }
}
