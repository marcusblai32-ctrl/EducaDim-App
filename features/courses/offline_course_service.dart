import 'package:flutter/foundation.dart';
import '../../core/db/app_database.dart';
import '../../core/db/cache_store.dart';
import '../../core/network/api_exception.dart';
import 'course_repository.dart';
import 'models.dart';
import 'offline_media.dart';

class OfflineCourse {
  OfflineCourse(this.courseId, this.title, this.lessons, this.skipped, this.createdAt);
  final int courseId;
  final String title;
  final int lessons, skipped;
  final DateTime createdAt;
}

/// Rend un cours lisible hors ligne : structure + contenu de chaque leçon en
/// SQLite, PLUS les fichiers médias (images, audio, PDF, vidéo) de toutes les
/// leçons et de tous les quiz, téléchargés sur l'appareil (offline_media.dart).
class OfflineCourseService extends ChangeNotifier {
  OfflineCourseService(this._db, this._repo, this._cache);
  final AppDatabase _db;
  final CourseRepository _repo;
  final CacheStore _cache;

  List<OfflineCourse> courses = [];
  int? busyCourseId;
  int progressDone = 0, progressTotal = 0;
  /// Nombre de fichiers médias qui n'ont pas pu être téléchargés au dernier essai.
  int mediaMissing = 0;
  int mediaTotal = 0;

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
      await _repo.detail(courseId);
      final cur = await _repo.curriculum(courseId);
      final lessons = cur.value.allLessons;
      final media = <String, String>{}; // url -> type
      progressTotal = lessons.length;
      var skipped = 0;
      for (final l in lessons) {
        try {
          final ls = await _repo.lesson(l.id);
          for (final m in OfflineMedia.urlsOfLesson(ls.value)) {
            media[m.url] = m.type;
          }
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
          final qd = await _repo.quiz(q.id);
          for (final u in OfflineMedia.urlsOfQuiz(qd.value)) {
            media[u] = 'image';
          }
          try {
            final pack = await _repo.downloadQuizPack(q.id); // bonnes réponses : correction hors ligne
            for (final u in OfflineMedia.urlsOfQuiz(pack)) {
              media[u] = 'image';
            }
          } catch (_) {}
        }
      } catch (_) {} // endpoint absent ou cours sans quiz
      // Images / audio / PDF / vidéo : téléchargement réel des fichiers.
      progressDone = 0;
      progressTotal = media.length;
      mediaTotal = media.length;
      notifyListeners();
      var mediaFailed = 0;
      for (final e in media.entries) {
        if (!await OfflineMedia.prefetch(e.key, e.value)) mediaFailed++;
        progressDone++;
        notifyListeners();
      }
      mediaMissing = mediaFailed;
      await _db.db.rawInsert(
        'INSERT OR REPLACE INTO offline_courses(course_id,title,lessons,skipped,created_at) VALUES(?,?,?,?,?)',
        [courseId, title, lessons.length - skipped, skipped, DateTime.now().millisecondsSinceEpoch],
      );
      await load();
    } finally {
      busyCourseId = null;
      notifyListeners();
    }
  }

  Future<void> remove(int courseId) async {
    final cur = await _cache.get('curriculum:$courseId');
    if (cur != null) {
      try {
        for (final l in (await _repo.curriculumFromJson(cur)).allLessons) {
          final lc = await _cache.get('lesson:${l.id}');
          if (lc != null) {
            try {
              for (final m in OfflineMedia.urlsOfLesson(Lesson.fromJson(lc))) {
                await OfflineMedia.evict(m.url);
              }
            } catch (_) {}
          }
          await _cache.delete('lesson:${l.id}');
        }
      } catch (_) {}
    }
    final fcCached = await _cache.get('flashcards:$courseId');
    if (fcCached != null) {
      for (final m in CourseFlashcards.fromJson(fcCached).modules) {
        await _cache.delete('flashcards:module:${m.moduleId}');
      }
    }
    await _cache.delete('flashcards:$courseId');
    final qc = await _cache.get('quizzes:$courseId');
    if (qc != null) {
      for (final q in QuizSummary.listFromJson(qc)) {
        await _cache.delete('quiz:${q.id}');
        await _cache.delete('quiz:offline:${q.id}');
      }
      await _cache.delete('quizzes:$courseId');
    }
    await _db.db.delete('offline_courses', where: 'course_id = ?', whereArgs: [courseId]);
    await load();
  }
}
