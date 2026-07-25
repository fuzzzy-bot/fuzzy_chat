// ignore_for_file: avoid_returning_this

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:fuzzy_chat/src/fuzzy_auth/storage/storage.dart';
import 'package:fuzzy_chat/src/fuzzy_chat/data/models/models.dart';
import 'package:fuzzy_chat/src/fuzzy_chat/storage/storage.dart';
import 'package:fuzzy_chat/src/fuzzy_vault/data/models/vault_item_type.dart';
import 'package:fuzzy_chat/src/fuzzy_vault/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web-compatible database using SharedPreferences with JSON serialization.
/// This mimics enough of Isar's API to work with the existing data sources.
class WebIsarDatabase {
  static final WebIsarDatabase _instance = WebIsarDatabase._internal();
  factory WebIsarDatabase() => _instance;
  WebIsarDatabase._internal();

  late SharedPreferences _prefs;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  // Collection accessors - each returns a WebIsarCollection for that type
  WebIsarCollection<StoredChatGeneralData> get storedChatGeneralDatas =>
      WebIsarCollection<StoredChatGeneralData>(_prefs, 'storedChatGeneralDatas', _storedChatGeneralDataFromJson, _storedChatGeneralDataToJson);

  WebIsarCollection<StoredChatPreferences> get storedChatPreferences =>
      WebIsarCollection<StoredChatPreferences>(_prefs, 'storedChatPreferences', _storedChatPreferencesFromJson, _storedChatPreferencesToJson);

  WebIsarCollection<StoredChatSecurityData> get storedChatSecurityDatas =>
      WebIsarCollection<StoredChatSecurityData>(_prefs, 'storedChatSecurityDatas', _storedChatSecurityDataFromJson, _storedChatSecurityDataToJson);

  WebIsarCollection<StoredMessageData> get storedMessageDatas =>
      WebIsarCollection<StoredMessageData>(_prefs, 'storedMessageDatas', _storedMessageDataFromJson, _storedMessageDataToJson);

  WebIsarCollection<StoredUserAuthPreferences> get storedUserAuthPreferences =>
      WebIsarCollection<StoredUserAuthPreferences>(_prefs, 'storedUserAuthPreferences', _storedUserAuthPreferencesFromJson, _storedUserAuthPreferencesToJson);

  WebIsarCollection<StoredVaultItem> get storedVaultItems =>
      WebIsarCollection<StoredVaultItem>(_prefs, 'storedVaultItems', _storedVaultItemFromJson, _storedVaultItemToJson);

  WebIsarCollection<StoredVaultGroup> get storedVaultGroups =>
      WebIsarCollection<StoredVaultGroup>(_prefs, 'storedVaultGroups', _storedVaultGroupFromJson, _storedVaultGroupToJson);

  WebIsarCollection<StoredVaultMetadata> get storedVaultMetadata =>
      WebIsarCollection<StoredVaultMetadata>(_prefs, 'storedVaultMetadata', _storedVaultMetadataFromJson, _storedVaultMetadataToJson);

  Future<T> writeTxn<T>(Future<T> Function() callback) async {
    return await callback();
  }
}

/// A collection that mimics Isar's collection API using SharedPreferences
class WebIsarCollection<T> {
  final SharedPreferences _prefs;
  final String _key;
  final T Function(Map<String, dynamic>) _fromJson;
  final Map<String, dynamic> Function(T) _toJson;

  WebIsarCollection(this._prefs, this._key, this._fromJson, this._toJson);

  List<T> get _items {
    final jsonString = _prefs.getString(_key);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error loading $_key: $e');
      return [];
    }
  }

  Future<void> _saveItems(List<T> items) async {
    final jsonList = items.map(_toJson).toList();
    await _prefs.setString(_key, jsonEncode(jsonList));
  }

  Future<int> put(T item) async {
    final items = _items;
    // Check if item already exists (by id field if available)
    final json = _toJson(item);
    final id = json['id'] as int?;
    if (id != null && id > 0) {
      final index = items.indexWhere((i) {
        final itemJson = _toJson(i);
        return itemJson['id'] == id;
      });
      if (index >= 0) {
        items[index] = item;
      } else {
        items.add(item);
      }
    } else {
      // Auto-increment id
      items.add(item);
    }
    await _saveItems(items);
    return id ?? items.length;
  }

  Future<List<int>> putAll(List<T> items) async {
    final ids = <int>[];
    for (final item in items) {
      ids.add(await put(item));
    }
    return ids;
  }

  Future<T?> get(int id) async {
    final items = _items;
    try {
      return items.firstWhere((i) {
        final json = _toJson(i);
        return json['id'] == id;
      });
    } catch (e) {
      return null;
    }
  }

  Future<List<T>> findAll() async => _items;

  Future<bool> delete(int id) async {
    final items = _items;
    final index = items.indexWhere((i) {
      final json = _toJson(i);
      return json['id'] == id;
    });
    if (index >= 0) {
      items.removeAt(index);
      await _saveItems(items);
      return true;
    }
    return false;
  }

  Future<int> deleteAll(List<int> ids) async {
    var count = 0;
    for (final id in ids) {
      if (await delete(id)) count++;
    }
    return count;
  }

  WebIsarQueryBuilder<T> filter() => WebIsarQueryBuilder<T>(_items, _toJson);

  WebIsarQueryBuilder<T> where() => WebIsarQueryBuilder<T>(_items, _toJson);
}

/// Mimics IsarQueryBuilder with filter/sort capabilities
class WebIsarQueryBuilder<T> {
  final Map<String, dynamic> Function(T) _toJson;
  List<T> _filteredItems;
  int? _offset;
  int? _limit;

  WebIsarQueryBuilder(List<T> allItems, this._toJson) : _filteredItems = List.from(allItems);

  WebIsarQueryBuilder<T> chatIdEqualTo(String value) {
    _filteredItems = _filteredItems.where((i) {
      final json = _toJson(i);
      return json['chatId'] == value;
    }).toList();
    return this;
  }

  WebIsarQueryBuilder<T> chatNameEqualTo(String value) {
    _filteredItems = _filteredItems.where((i) {
      final json = _toJson(i);
      return json['chatName'] == value;
    }).toList();
    return this;
  }

  WebIsarQueryBuilder<T> groupIdEqualTo(String value) {
    _filteredItems = _filteredItems.where((i) {
      final json = _toJson(i);
      return json['groupId'] == value;
    }).toList();
    return this;
  }

  WebIsarQueryBuilder<T> itemIdEqualTo(String value) {
    _filteredItems = _filteredItems.where((i) {
      final json = _toJson(i);
      return json['itemId'] == value;
    }).toList();
    return this;
  }

  WebIsarQueryBuilder<T> sortBySentAt() {
    _filteredItems.sort((a, b) {
      final jsonA = _toJson(a);
      final jsonB = _toJson(b);
      final dateA = DateTime.tryParse(jsonA['sentAt']?.toString() ?? '') ?? DateTime(1970);
      final dateB = DateTime.tryParse(jsonB['sentAt']?.toString() ?? '') ?? DateTime(1970);
      return dateA.compareTo(dateB);
    });
    return this;
  }

  WebIsarQueryBuilder<T> sortBySentAtDesc() {
    _filteredItems.sort((a, b) {
      final jsonA = _toJson(a);
      final jsonB = _toJson(b);
      final dateA = DateTime.tryParse(jsonA['sentAt']?.toString() ?? '') ?? DateTime(1970);
      final dateB = DateTime.tryParse(jsonB['sentAt']?.toString() ?? '') ?? DateTime(1970);
      return dateB.compareTo(dateA);
    });
    return this;
  }

  WebIsarQueryBuilder<T> offset(int value) {
    _offset = value;
    return this;
  }

  WebIsarQueryBuilder<T> limit(int value) {
    _limit = value;
    return this;
  }

  Future<List<T>> findAll() async {
    var result = List.from(_filteredItems);
    if (_offset != null) {
      result = result.skip(_offset!).toList();
    }
    if (_limit != null) {
      result = result.take(_limit!).toList();
    }
    return result.cast<T>();
  }

  Future<T?> findFirst() async {
    final all = await findAll();
    return all.isEmpty ? null : all.first;
  }

  Future<int> deleteAll() async {
    // This would need to modify the underlying storage
    // For now, return 0
    return 0;
  }
}

// JSON serialization helpers for each model type
// These need to match the Isar model structure

/// Mirrors `Isar.autoIncrement` so this web stub does not have to depend on Isar.
const int _autoIncrementId = -9223372036854775808;

DateTime _parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value) ?? DateTime.now() : DateTime.now();

Map<String, dynamic> _storedChatGeneralDataToJson(StoredChatGeneralData item) {
  return {
    'id': item.id,
    'chatId': item.chatId,
    'chatName': item.chatName,
    'setupStatus': item.setupStatus.index,
    'createdAt': item.createdAt.toIso8601String(),
    'didAcceptInvitation': item.didAcceptInvitation,
  };
}

StoredChatGeneralData _storedChatGeneralDataFromJson(Map<String, dynamic> json) {
  final setupStatusIndex = json['setupStatus'] as int?;
  return StoredChatGeneralData()
    ..id = json['id'] as int? ?? _autoIncrementId
    ..chatId = json['chatId'] as String? ?? ''
    ..chatName = json['chatName'] as String? ?? ''
    ..setupStatus = setupStatusIndex != null && setupStatusIndex < ChatSetupStatus.values.length
        ? ChatSetupStatus.values[setupStatusIndex]
        : ChatSetupStatus.invited
    ..createdAt = _parseDate(json['createdAt'])
    ..didAcceptInvitation = json['didAcceptInvitation'] as bool? ?? false;
}

Map<String, dynamic> _storedChatPreferencesToJson(StoredChatPreferences item) {
  return {
    'id': item.id,
    'theme': item.theme,
    'showTimestamps': item.showTimestamps,
    'lastUpdated': item.lastUpdated.toIso8601String(),
  };
}

StoredChatPreferences _storedChatPreferencesFromJson(Map<String, dynamic> json) {
  return StoredChatPreferences()
    ..id = json['id'] as int? ?? _autoIncrementId
    ..theme = json['theme'] as String?
    ..showTimestamps = json['showTimestamps'] as bool? ?? true
    ..lastUpdated = _parseDate(json['lastUpdated']);
}

Map<String, dynamic> _storedChatSecurityDataToJson(StoredChatSecurityData item) {
  return {
    'id': item.id,
    'chatId': item.chatId,
    'invitationFilePath': item.invitationFilePath,
    'acceptanceFilePath': item.acceptanceFilePath,
    'encryptedSymmetricKey': item.encryptedSymmetricKey,
    'createdAt': item.createdAt.toIso8601String(),
  };
}

StoredChatSecurityData _storedChatSecurityDataFromJson(Map<String, dynamic> json) {
  return StoredChatSecurityData()
    ..id = json['id'] as int? ?? _autoIncrementId
    ..chatId = json['chatId'] as String? ?? ''
    ..invitationFilePath = json['invitationFilePath'] as String?
    ..acceptanceFilePath = json['acceptanceFilePath'] as String?
    ..encryptedSymmetricKey = json['encryptedSymmetricKey'] as String?
    ..createdAt = _parseDate(json['createdAt']);
}

Map<String, dynamic> _storedMessageDataToJson(StoredMessageData item) {
  return {
    'id': item.id,
    'chatId': item.chatId,
    'encryptedMessage': item.encryptedMessage,
    'messageType': item.messageType,
    'sentAt': item.sentAt.toIso8601String(),
    'isSent': item.isSent,
  };
}

StoredMessageData _storedMessageDataFromJson(Map<String, dynamic> json) {
  return StoredMessageData()
    ..id = json['id'] as int? ?? _autoIncrementId
    ..chatId = json['chatId'] as String? ?? ''
    ..encryptedMessage = json['encryptedMessage'] as String? ?? ''
    ..messageType = json['messageType'] as String? ?? MessageType.text.name
    ..sentAt = _parseDate(json['sentAt'])
    ..isSent = json['isSent'] as bool? ?? false;
}

Map<String, dynamic> _storedUserAuthPreferencesToJson(StoredUserAuthPreferences item) {
  return {
    'id': item.id,
    'isAuthenticationOnceEnabled': item.isAuthenticationOnceEnabled,
    'lastUpdated': item.lastUpdated.toIso8601String(),
  };
}

// `StoredUserAuthPreferences.id` is a final singleton id (always 1), so it is
// written to JSON for lookups but never assigned back on read.
StoredUserAuthPreferences _storedUserAuthPreferencesFromJson(Map<String, dynamic> json) {
  return StoredUserAuthPreferences()
    ..isAuthenticationOnceEnabled = json['isAuthenticationOnceEnabled'] as bool? ?? false
    ..lastUpdated = _parseDate(json['lastUpdated']);
}

Map<String, dynamic> _storedVaultItemToJson(StoredVaultItem item) {
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

StoredVaultItem _storedVaultItemFromJson(Map<String, dynamic> json) {
  final typeIndex = json['type'] as int?;
  return StoredVaultItem()
    ..id = json['id'] as int? ?? _autoIncrementId
    ..itemId = json['itemId'] as String? ?? ''
    ..title = json['title'] as String? ?? ''
    ..groupId = json['groupId'] as String? ?? ''
    ..type = typeIndex != null && typeIndex < VaultItemType.values.length
        ? VaultItemType.values[typeIndex]
        : VaultItemType.note
    ..tags = (json['tags'] as List<dynamic>?)?.cast<String>() ?? <String>[]
    ..isFavorite = json['isFavorite'] as bool? ?? false
    ..hasCustomPassword = json['hasCustomPassword'] as bool? ?? false
    ..createdAt = _parseDate(json['createdAt'])
    ..updatedAt = _parseDate(json['updatedAt'])
    ..contentVersion = json['contentVersion'] as int? ?? 1;
}

Map<String, dynamic> _storedVaultGroupToJson(StoredVaultGroup item) {
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

StoredVaultGroup _storedVaultGroupFromJson(Map<String, dynamic> json) {
  return StoredVaultGroup()
    ..id = json['id'] as int? ?? _autoIncrementId
    ..groupId = json['groupId'] as String? ?? ''
    ..name = json['name'] as String? ?? ''
    ..emoji = json['emoji'] as String? ?? ''
    ..colorIndex = json['colorIndex'] as int? ?? 0
    ..sortOrder = json['sortOrder'] as int? ?? 0
    ..hasCustomPassword = json['hasCustomPassword'] as bool? ?? false
    ..createdAt = _parseDate(json['createdAt'])
    ..updatedAt = _parseDate(json['updatedAt']);
}

Map<String, dynamic> _storedVaultMetadataToJson(StoredVaultMetadata item) {
  return {
    'id': item.id,
    'vaultId': item.vaultId,
    'verificationTokenBase64': item.verificationTokenBase64,
    'masterSaltBase64': item.masterSaltBase64,
    'createdAt': item.createdAt.toIso8601String(),
    'lastUnlockedAt': item.lastUnlockedAt.toIso8601String(),
    'autoLockMinutes': item.autoLockMinutes,
    'customDirectoryPath': item.customDirectoryPath,
  };
}

StoredVaultMetadata _storedVaultMetadataFromJson(Map<String, dynamic> json) {
  return StoredVaultMetadata()
    ..id = json['id'] as int? ?? _autoIncrementId
    ..vaultId = json['vaultId'] as String? ?? ''
    ..verificationTokenBase64 = json['verificationTokenBase64'] as String? ?? ''
    ..masterSaltBase64 = json['masterSaltBase64'] as String? ?? ''
    ..createdAt = _parseDate(json['createdAt'])
    ..lastUnlockedAt = _parseDate(json['lastUnlockedAt'])
    ..autoLockMinutes = json['autoLockMinutes'] as int? ?? 5
    ..customDirectoryPath = json['customDirectoryPath'] as String?;
}
