import 'dart:convert';
import 'app_database.dart';

/// Cache JSON des réponses API (lecture hors ligne).
class CacheStore {
  CacheStore(this._d);
  final AppDatabase _d;

  Future<void> put(String key, Object? data) async {
    await _d.db.rawInsert(
      'INSERT OR REPLACE INTO api_cache(key, json, updated_at) VALUES(?,?,?)',
      [key, jsonEncode(data), DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<dynamic> get(String key) async {
    final r = await _d.db.query('api_cache', where: 'key = ?', whereArgs: [key]);
    if (r.isEmpty) return null;
    return jsonDecode(r.first['json'] as String);
  }

  Future<void> delete(String key) =>
      _d.db.delete('api_cache', where: 'key = ?', whereArgs: [key]);

  Future<void> deleteAll() => _d.db.delete('api_cache');
}
