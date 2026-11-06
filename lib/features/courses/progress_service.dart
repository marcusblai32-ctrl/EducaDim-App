import 'package:flutter/foundation.dart';
import '../../core/db/app_database.dart';
import '../../core/db/outbox_repository.dart';
import '../../core/sync/sync_service.dart';

/// Progression locale. Le backend n'expose pas encore d'endpoint d'écriture de
/// progression : chaque leçon terminée est enregistrée localement ET placée dans
/// la file (`lesson_completed`, id stable = pas de doublon) pour envoi dès que
/// l'endpoint sera branché dans SyncGateway.
class ProgressService extends ChangeNotifier {
  ProgressService(this._db, this._outbox, this._sync);
  final AppDatabase _db;
  final OutboxRepository _outbox;
  final SyncService _sync;

  final Map<int, int> _done = {}; // lessonId -> courseId
  Set<int> get completedLessons => _done.keys.toSet();
  int get totalCompleted => _done.length;
  int doneInCourse(int courseId) => _done.values.where((c) => c == courseId).length;
  bool isDone(int lessonId) => _done.containsKey(lessonId);

  Future<void> load() async {
    final rows = await _db.db.query('local_progress');
    _done
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r['lesson_id'] as int, r['course_id'] as int)));
    notifyListeners();
  }

  Future<void> complete(int lessonId, int courseId) async {
    if (isDone(lessonId)) return;
    final now = DateTime.now();
    await _db.db.insert('local_progress', {
      'lesson_id': lessonId,
      'course_id': courseId,
      'completed_at': now.millisecondsSinceEpoch,
    });
    await _outbox.enqueue(
      'lesson_completed',
      {
        'lesson_id': lessonId,
        'course_id': courseId,
        'completed_at': now.toUtc().toIso8601String(),
      },
      id: 'lesson-$lessonId',
    );
    _done[lessonId] = courseId;
    notifyListeners();
    await _sync.refreshCount();
  }
}
