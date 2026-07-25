import 'package:shared_preferences/shared_preferences.dart';

/// Web stub for secure storage - uses SharedPreferences as fallback
class WebSecureStorage {
  static final WebSecureStorage _instance = WebSecureStorage._internal();
  factory WebSecureStorage() => _instance;
  WebSecureStorage._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> write({required String key, required String? value}) async {
    if (_prefs == null) return;
    if (value == null) {
      await _prefs!.remove(key);
    } else {
      await _prefs!.setString(key, value);
    }
  }

  Future<String?> read({required String key}) async {
    if (_prefs == null) return null;
    return _prefs!.getString(key);
  }

  Future<void> delete({required String key}) async {
    if (_prefs == null) return;
    await _prefs!.remove(key);
  }

  Future<void> deleteAll() async {
    if (_prefs == null) return;
    await _prefs!.clear();
  }

  Future<Map<String, String>> readAll() async {
    if (_prefs == null) return {};
    final all = _prefs!.getKeys();
    final result = <String, String>{};
    for (final key in all) {
      final val = _prefs!.getString(key);
      if (val != null) result[key] = val;
    }
    return result;
  }
}
