import 'package:dio/dio.dart';
import '../../core/db/cache_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'models.dart';

/// Accès aux endpoints réels : /courses/, /courses/<id>/, /curriculum/, /lessons/<id>/.
/// En cas de coupure réseau, retombe sur le dernier contenu mis en cache.
class CourseRepository {
  CourseRepository(this._api, this._cache);
  final ApiClient _api;
  final CacheStore _cache;

  Future<Loaded<T>> _get<T>(
    String path,
    String cacheKey,
    T Function(dynamic) parse, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _api.dio.get(path, queryParameters: query);
      await _cache.put(cacheKey, res.data);
      return Loaded(parse(res.data));
    } on DioException catch (e) {
      final ex = mapDio(e);
      if (ex.isOffline) {
        final cached = await _cache.get(cacheKey);
        if (cached != null) return Loaded(parse(cached), fromCache: true);
      }
      throw ex;
    }
  }

  Future<Loaded<CoursePage>> catalog({String search = '', String? prix, int page = 1}) {
    final q = <String, dynamic>{
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (prix != null) 'prix': prix,
      if (page > 1) 'page': page,
    };
    return _get('courses/', 'courses:list:${search.trim()}:${prix ?? ''}:$page',
        CoursePage.fromJson,
        query: q);
  }

  /// Cours auxquels l'utilisateur a accès (inscription active, abonnement,
  /// cours gratuit) : toutes les pages du catalogue filtrées sur access.has_access.
  Future<Loaded<List<Course>>> myCourses() async {
    final all = <Course>[];
    var fromCache = false;
    for (var p = 1; p <= 50; p++) {
      final r = await catalog(page: p);
      fromCache = fromCache || r.fromCache;
      all.addAll(r.value.results);
      if (!r.value.hasNext) break;
    }
    return Loaded(all.where((c) => c.access.hasAccess).toList(), fromCache: fromCache);
  }

  Future<Loaded<CourseDetail>> detail(int id) =>
      _get('courses/$id/', 'course:$id', CourseDetail.fromJson);

  Future<Loaded<Curriculum>> curriculum(int id) =>
      _get('courses/$id/curriculum/', 'curriculum:$id', Curriculum.fromJson);

  Future<Loaded<ProgressSummary>> progress() =>
      _get('me/progress/', 'me:progress', ProgressSummary.fromJson);

  Future<Loaded<List<ActivityItem>>> activity() =>
      _get('me/activity/', 'me:activity', ActivityItem.listFromJson);

  Future<Loaded<List<Flashcard>>> flashcards(int courseId) => _get(
      'courses/$courseId/flashcards/', 'flashcards:$courseId', Flashcard.listFromJson);

  Future<Loaded<Lesson>> lesson(int id) =>
      _get('lessons/$id/', 'lesson:$id', Lesson.fromJson);

  Future<Curriculum> curriculumFromJson(dynamic json) async => Curriculum.fromJson(json);
}
