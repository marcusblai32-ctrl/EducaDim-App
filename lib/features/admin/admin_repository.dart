import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/db/cache_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

/// Droits de gestion de contenu (admin / staff avec permissions Django).
/// L'affichage des boutons suit la réponse du serveur ; le serveur re-vérifie
/// chaque action (le bouton n'est jamais la sécurité).
class AdminAccess extends ChangeNotifier {
  AdminAccess(this._api, this._cache);
  final ApiClient _api;
  final CacheStore _cache;

  bool canManage = false;

  Future<void> load() async {
    try {
      final res = await _api.dio.get('admin/capabilities/');
      canManage = res.data is Map && res.data['can_manage'] == true;
      await _cache.put('admin:caps', {'can_manage': canManage});
    } on DioException {
      final c = await _cache.get('admin:caps'); // hors ligne : dernier état connu
      canManage = c is Map && c['can_manage'] == true;
    }
    notifyListeners();
  }

  void clear() {
    canManage = false;
    notifyListeners();
  }
}

class AdminRepository {
  AdminRepository(this._api);
  final ApiClient _api;

  Future<dynamic> _get(String path) async {
    try {
      return (await _api.dio.get(path)).data;
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  Future<dynamic> _send(String method, String path, Map<String, dynamic> data) async {
    try {
      final res = await _api.dio.request(path, data: data, options: Options(method: method));
      return res.data;
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  Future<Map> meta() async => (await _get('admin/meta/')) as Map;
  Future<List> courses() async => ((await _get('admin/courses/')) as Map)['courses'] as List;
  Future<Map> tree(int courseId) async => (await _get('admin/courses/$courseId/tree/')) as Map;

  Future<Map> createCourse(Map<String, dynamic> d) async =>
      (await _send('POST', 'admin/courses/', d)) as Map;
  Future<void> setCoursePublished(int id, bool v) =>
      _send('PATCH', 'admin/courses/$id/', {'publie': v});
  Future<void> createUnite(int courseId, Map<String, dynamic> d) =>
      _send('POST', 'admin/courses/$courseId/unites/', d);
  Future<void> createModule(int uniteId, Map<String, dynamic> d) =>
      _send('POST', 'admin/unites/$uniteId/modules/', d);
  Future<void> createLecon(int moduleId, Map<String, dynamic> d) =>
      _send('POST', 'admin/modules/$moduleId/lecons/', d);
  Future<void> createSection(int leconId, Map<String, dynamic> d) =>
      _send('POST', 'admin/lecons/$leconId/sections/', d);
  Future<void> createContenu(int sectionId, Map<String, dynamic> d) =>
      _send('POST', 'admin/sections/$sectionId/contenus/', d);
  Future<Map> createQuiz(Map<String, dynamic> d) async =>
      (await _send('POST', 'admin/quizzes/', d)) as Map;
  Future<void> setQuizPublished(int id, bool v) =>
      _send('PATCH', 'admin/quizzes/$id/', {'publie': v});
  Future<Map> addQuestion(int quizId, Map<String, dynamic> d) async =>
      (await _send('POST', 'admin/quizzes/$quizId/questions/', d)) as Map;
}
