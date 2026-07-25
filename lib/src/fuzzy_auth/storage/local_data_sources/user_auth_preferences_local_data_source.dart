import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/user_auth_preferences.dart';
import '../storage_models/stored_user_auth_preferences.dart';

class UserAuthPreferencesLocalDataSource {
  final Isar? isar;
  SharedPreferences? _webPrefs;
  static const String _webKey = 'user_auth_preferences';

  UserAuthPreferencesLocalDataSource({this.isar});

  Future<void> _initWeb() async {
    _webPrefs ??= await SharedPreferences.getInstance();
  }

  Future<StoredUserAuthPreferences?> get() async {
    if (kIsWeb) {
      await _initWeb();
      final jsonString = _webPrefs!.getString(_webKey);
      if (jsonString == null || jsonString.isEmpty) return null;
      try {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return _fromJson(json);
      } catch (e) {
        return null;
      }
    }
    if (isar == null) return null;
    return isar!.storedUserAuthPreferences.get(1);
  }

  Future<void> update(UserAuthPreferences model) async {
    if (kIsWeb) {
      await _initWeb();
      final storedModel = StoredUserAuthPreferences()
        ..isAuthenticationOnceEnabled = model.isAuthenticationOnceEnabled
        ..lastUpdated = DateTime.now();
      await _webPrefs!.setString(_webKey, jsonEncode(_toJson(storedModel)));
      return;
    }
    if (isar == null) return;
    final storedModel = StoredUserAuthPreferences()
      ..isAuthenticationOnceEnabled = model.isAuthenticationOnceEnabled
      ..lastUpdated = DateTime.now();

    await isar!.writeTxn(() async {
      await isar!.storedUserAuthPreferences.put(storedModel);
    });
  }

  Future<bool> delete() async {
    if (kIsWeb) {
      await _initWeb();
      return await _webPrefs!.remove(_webKey);
    }
    if (isar == null) return false;
    return isar!.writeTxn(() async {
      return isar!.storedUserAuthPreferences.delete(1);
    });
  }

  Map<String, dynamic> _toJson(StoredUserAuthPreferences item) {
    return {
      'id': item.id,
      'isAuthenticationOnceEnabled': item.isAuthenticationOnceEnabled,
      'lastUpdated': item.lastUpdated.toIso8601String(),
    };
  }

  StoredUserAuthPreferences _fromJson(Map<String, dynamic> json) {
    return StoredUserAuthPreferences()
      ..isAuthenticationOnceEnabled = json['isAuthenticationOnceEnabled'] as bool? ?? false
      ..lastUpdated = DateTime.parse(json['lastUpdated'] as String);
  }
}
