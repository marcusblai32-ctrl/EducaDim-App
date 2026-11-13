import 'package:flutter/foundation.dart';
import '../../core/db/app_database.dart';
import '../../core/db/cache_store.dart';
import '../../core/network/api_exception.dart';
import 'course_repository.dart';
import 'models.dart';

class OfflineCourse {
  OfflineCourse(this.courseId, this.title, this.lessons, this.skipped, this.createdAt);
  final int courseId;
  final String title;
  final int lessons, skipped;
  final DateTime createdAt;
}

/// Rend un cours lisible hors ligne : structure + contenu texte/URL de chaque
/// leçon sont mis en cache en SQLite. Les fichiers médias eux-mêmes (vidéo,
/// audio, PDF) ne sont PAS téléchargés : le backend n'expose pas encore
/// d'endpoint `manifest` / URL signées (voir docs/API_CONTRACT.md).
class OfflineCourseService extends ChangeNotifier {
  OfflineCourseService(this._db, this._repo, this._cache);

  /// Lit la date de fin d'accès du cours (null = sans fin). Fourni par OfflineAccess.
  Future<int?> Function(int courseId)? accessUntilFor;
  final AppDatabase _db;
  final CourseRepository _repo;
  final CacheStore _cache;

  List<OfflineCourse> courses = [];
  int? busyCourseId;
  int progressDone = 0, progressTotal = 0;

  bool isOffline(int courseId) => courses.any((c) => c.courseId == courseId);

  Future<void> load() async {
    final rows = await _db.db.query('offline_courses', orderBy: 'created_at DESC');
    courses = rows
        .map((r) => OfflineCourse(
              r['course_id'] as int,
              r['title'] as String,
              r['lessons'] as int,
              r['skipped'] as int,
              DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
            ))
        .toList();
    notifyListeners();
  }

  Future<void> download(int courseId, String title) async {
    if (busyCourseId != null) return;
    busyCourseId = courseId;
    progressDone = 0;
    notifyListeners();
    try {
      final until = accessUntilFor == null ? null : await accessUntilFor!(courseId);
      await _repo.detail(courseId);
      final cur = await _repo.curriculum(courseId);
      final lessons = cur.value.allLessons;
      progressTotal = lessons.length;
      var skipped = 0;
      for (final l in lessons) {
        try {
          await _repo.lesson(l.id);
        } on LessonQuizRequired {
          skipped++; // leçon verrouillée par un quiz à réussir
        }
        progressDone++;
        notifyListeners();
      }
      try {
        final fc = await _repo.courseFlashcards(courseId);
        for (final m in fc.value.modules) {
          await _repo.moduleFlashcards(m.moduleId);
        }
      } catch (_) {} // cours sans flashcards ou fonctionnalité indisponible
      try {
        final qs = await _repo.quizzes(courseId);
        for (final q in qs.value.where((q) => q.compatible)) {
          await _repo.quiz(q.id);
          try {
            await _repo.downloadQuizPack(q.id); // bonnes réponses : correction hors ligne
          } catch (_) {}
        }
      } catch (_) {} // endpoint absent ou cours sans quiz
      await _db.db.rawInsert(
        'INSERT OR REPLACE INTO offline_courses(course_id,title,lessons,skipped,created_at,access_until) VALUES(?,?,?,?,?,?)',
        [courseId, title, lessons.length - skipped, skipped, DateTime.now().millisecondsSinceEpoch, until],
      );
      await load();
    } finally {
      busyCourseId = null;
      notifyListeners();
    }
  }

  /// Toutes les clés de cache d'un cours (pour le bloquer ou le supprimer).
  Future<List<String>> cacheKeysFor(int courseId) async {
    final keys = <String>['course:$courseId', 'curriculum:$courseId', 'flashcards:$courseId', 'quizzes:$courseId'];
    final cur = await _cache.get('curriculum:$courseId');
    if (cur != null) {
      try {
        for (final l in (await _repo.curriculumFromJson(cur)).allLessons) {
          keys.add('lesson:${l.id}');
        }
      } catch (_) {}
    }
    final fcCached = await _cache.get('flashcards:$courseId');
    if (fcCached != null) {
      try {
        for (final m in CourseFlashcards.fromJson(fcCached).modules) {
          keys.add('flashcards:module:${m.moduleId}');
        }
      } catch (_) {}
    }
    final qc = await _cache.get('quizzes:$courseId');
    if (qc != null) {
      try {
        for (final q in QuizSummary.listFromJson(qc)) {
          keys.add('quiz:${q.id}');
        }
      } catch (_) {}
    }
    return keys;
  }

  Future<void> remove(int courseId) async {
    for (final k in await cacheKeysFor(courseId)) {
      await _cache.delete(k);
    }
    await _db.db.delete('offline_courses', where: 'course_id = ?', whereArgs: [courseId]);
    await load();
  }
}
