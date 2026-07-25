import 'package:shared_preferences/shared_preferences.dart';

/// Web stub for Isar - provides in-memory storage using SharedPreferences
class WebIsarStub {
  static final WebIsarStub _instance = WebIsarStub._internal();
  factory WebIsarStub() => _instance;
  WebIsarStub._internal();

  SharedPreferences? _prefs;
  final Map<String, dynamic> _memory = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  T? get<T>(String key) {
    if (_memory.containsKey(key)) return _memory[key] as T?;
    if (_prefs == null) return null;
    final val = _prefs!.get(key);
    if (val != null) _memory[key] = val;
    return val as T?;
  }

  Future<void> put<T>(String key, T value) async {
    _memory[key] = value;
    if (_prefs == null) return;
    if (value is String) await _prefs!.setString(key, value);
    if (value is int) await _prefs!.setInt(key, value);
    if (value is bool) await _prefs!.setBool(key, value);
    if (value is double) await _prefs!.setDouble(key, value);
    if (value is List<String>) await _prefs!.setStringList(key, value);
  }

  Future<void> delete(String key) async {
    _memory.remove(key);
    await _prefs?.remove(key);
  }

  Future<void> clear() async {
    _memory.clear();
    await _prefs?.clear();
  }
}

/// Stub for Isar collection queries on web
class WebIsarCollectionStub<T> {
  final List<T> _items = [];
  int _autoIncrementId = 0;

  Future<int> put(T item) async {
    _items.add(item);
    return ++_autoIncrementId;
  }

  Future<List<int>> putAll(List<T> items) async {
    final ids = <int>[];
    for (final item in items) {
      ids.add(await put(item));
    }
    return ids;
  }

  Future<T?> get(int id) async {
    if (id <= 0 || id > _items.length) return null;
    return _items[id - 1];
  }

  Future<List<T?>> getAll(List<int> ids) async {
    return ids.map((id) => id > 0 && id <= _items.length ? _items[id - 1] : null).toList();
  }

  Future<List<T>> getAllSync() async => List.from(_items);

  Future<bool> delete(int id) async {
    if (id <= 0 || id > _items.length) return false;
    _items.removeAt(id - 1);
    return true;
  }

  Future<int> deleteAll(List<int> ids) async {
    var count = 0;
    for (final id in ids) {
      if (await delete(id)) count++;
    }
    return count;
  }

  Future<List<T>> where() async => List.from(_items);

  Future<T?> getByIndex(String indexName, List<dynamic> values) async => null;

  Future<List<T?>> getAllByIndex(String indexName, List<List<dynamic>> values) async => [];

  Future<bool> deleteByIndex(String indexName, List<dynamic> values) async => false;

  Future<int> deleteAllByIndex(String indexName, List<List<dynamic>> values) async => 0;

  Future<int> putByIndex(String indexName, T object) async => put(object);

  Future<List<int>> putAllByIndex(String indexName, List<T> objects) async => putAll(objects);
}
