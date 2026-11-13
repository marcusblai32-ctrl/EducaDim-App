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

  /// Vrai = le contenu en cache de cette clé est bloqué (abonnement expiré) : illisible même hors ligne.
  bool Function(String cacheKey)? cacheBlocked;

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
        final cached = (cacheBlocked?.call(cacheKey) ?? false) ? null : await _cache.get(cacheKey);
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

  /// Inscription explicite à un cours gratuit (idempotent). Lance ApiException en cas d'échec.
  Future<void> enrollFree(int courseId) async {
    try {
      await _api.dio.post('courses/$courseId/enroll/');
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  /// Abonnements qui contiennent ce cours (liste vide = pas d'option abonnement).
  Future<List<CoursePlan>> plans(int courseId) async {
    try {
      final r = await _api.dio.get('courses/$courseId/plans/');
      final list = (r.data is Map ? r.data['plans'] : null) as List? ?? const [];
      return list.map((e) => CoursePlan.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  Future<Loaded<CourseDetail>> detail(int id) =>
      _get('courses/$id/', 'course:$id', CourseDetail.fromJson);

  Future<Loaded<Curriculum>> curriculum(int id) =>
      _get('courses/$id/curriculum/', 'curriculum:$id', Curriculum.fromJson);

  Future<Loaded<ProgressSummary>> progress() =>
      _get('me/progress/', 'me:progress', ProgressSummary.fromJson);

  Future<Loaded<List<ActivityItem>>> activity() =>
      _get('me/activity/', 'me:activity', ActivityItem.listFromJson);

  Future<Loaded<CourseFlashcards>> courseFlashcards(int courseId) =>
      _get('courses/$courseId/flashcards/', 'flashcards:$courseId', CourseFlashcards.fromJson);

  Future<Loaded<List<Flashcard>>> moduleFlashcards(int moduleId) => _get(
      'modules/$moduleId/flashcards/', 'flashcards:module:$moduleId', Flashcard.listFromJson);

  Future<Loaded<List<QuizSummary>>> quizzes(int courseId) =>
      _get('courses/$courseId/quizzes/', 'quizzes:$courseId', QuizSummary.listFromJson);

  Future<Loaded<QuizDetail>> quiz(int id) =>
      _get('quizzes/$id/', 'quiz:$id', QuizDetail.fromJson);

  /// Paquet hors ligne : quiz + bonnes réponses + explications (pour corriger sans réseau).
  Future<QuizDetail> downloadQuizPack(int id) async {
    try {
      final res = await _api.dio.get('quizzes/$id/offline/');
      await _cache.put('quiz:offline:$id', res.data);
      await _cache.put('quiz:$id', res.data); // l'écran d'intro lit aussi ce cache
      return QuizDetail.fromJson(res.data);
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  Future<QuizDetail?> cachedQuizPack(int id) async {
    final c = await _cache.get('quiz:offline:$id');
    if (c == null) return null;
    final q = QuizDetail.fromJson(c);
    return q.gradable ? q : null;
  }

  Future<void> removeQuizPack(int id) => _cache.delete('quiz:offline:$id');

  /// Mémorise localement le résultat d'une tentative faite hors ligne.
  Future<void> saveLocalResult(QuizResult r) => _cache.put('quiz:attempt:${r.attemptId}', r.toJson());

  /// Démarre ou reprend une tentative (en ligne obligatoire).
  Future<QuizAttempt> startQuiz(int quizId) async {
    try {
      final res = await _api.dio.post('quizzes/$quizId/start/');
      return QuizAttempt.fromJson(res.data);
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  /// Envoi direct ; le résultat est mis en cache pour la lecture hors ligne.
  Future<QuizResult> submitQuiz(int attemptId, List<Map<String, dynamic>> answers) async {
    try {
      final res = await _api.dio
          .post('quiz-attempts/$attemptId/submit/', data: {'answers': answers});
      await _cache.put('quiz:attempt:$attemptId', res.data);
      return QuizResult.fromJson(res.data);
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  Future<Loaded<QuizResult>> quizResult(int attemptId) async {
    if (attemptId < 0) {
      // tentative locale (hors ligne) : résultat stocké sur l'appareil, puis remplacé après synchro
      final c = await _cache.get('quiz:attempt:$attemptId');
      if (c != null) return Loaded(QuizResult.fromJson(c));
      throw ApiException('Résultat introuvable.');
    }
    return _quizResultNet(attemptId);
  }

  Future<Loaded<QuizResult>> _quizResultNet(int attemptId) =>
      _get('quiz-attempts/$attemptId/', 'quiz:attempt:$attemptId', QuizResult.fromJson);

  Future<Loaded<Lesson>> lesson(int id) =>
      _get('lessons/$id/', 'lesson:$id', Lesson.fromJson);

  Future<Curriculum> curriculumFromJson(dynamic json) async => Curriculum.fromJson(json);
}

class CoursePlan {
  CoursePlan({
    required this.id,
    required this.name,
    required this.price,
    required this.free,
    required this.durationDays,
    required this.maxCourses,
    required this.subscribeUrl,
  });
  final int id;
  final String name;
  final double price;
  final bool free;
  final int durationDays;
  final int maxCourses;
  final String subscribeUrl;

  factory CoursePlan.fromJson(Map<String, dynamic> j) => CoursePlan(
        id: (j['id'] as num).toInt(),
        name: '${j['name'] ?? ''}',
        price: ((j['price'] ?? 0) as num).toDouble(),
        free: j['free'] == true,
        durationDays: ((j['duration_days'] ?? 0) as num).toInt(),
        maxCourses: ((j['max_courses'] ?? 0) as num).toInt(),
        subscribeUrl: '${j['subscribe_url'] ?? ''}',
      );

  String get priceLabel => free ? 'Gratuit' : '${price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2)} HTG';

  String get durationLabel {
    if (durationDays >= 365 && durationDays % 365 == 0) return '${durationDays ~/ 365} an';
    if (durationDays >= 30 && durationDays % 30 == 0) return '${durationDays ~/ 30} mois';
    if (durationDays % 7 == 0) return '${durationDays ~/ 7} sem.';
    return '$durationDays j';
  }
}
