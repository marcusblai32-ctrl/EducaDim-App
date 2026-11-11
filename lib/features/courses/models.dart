import '../../core/i18n/lang.dart';

// Modèles alignés sur mobile_api/serializers.py du backend Django.

String? _s(Map m, String k) => m[k] is String ? m[k] as String : null;
int? _i(Map m, String k) => m[k] is int ? m[k] as int : null;
bool _b(Map m, String k) => m[k] == true;
Map _m(dynamic v) => v is Map ? v : const {};
List _l(dynamic v) => v is List ? v : const [];

class CourseAccess {
  CourseAccess(this.hasAccess, this.source, this.enrollmentStatus, this.expiresAt);
  final bool hasAccess;
  final String? source; // enrollment | subscription | free | null
  final String? enrollmentStatus; // pending|active|rejected|cancelled|null
  final String? expiresAt;
  factory CourseAccess.fromJson(dynamic j) {
    final m = _m(j);
    final source = _s(m, 'source');
    // Un cours gratuit n'ouvre l'accès qu'après inscription explicite (source « enrollment »),
    // même si un ancien serveur renvoie encore « free ».
    return CourseAccess(_b(m, 'has_access') && source != 'free', source,
        _s(m, 'enrollment_status'), _s(m, 'expires_at'));
  }
}

class Course {
  Course({
    required this.id,
    required this.titre,
    required this.description,
    this.image,
    required this.prix,
    required this.estPayant,
    required this.duree,
    this.categorie,
    this.niveau,
    required this.inscriptionPossible,
    required this.access,
  });
  final int id;
  final String titre;
  final String description;
  final String? image;
  final String prix; // décimal sous forme de texte, ex. "1500.00"
  final bool estPayant;
  final int duree; // heures
  final String? categorie;
  final String? niveau;
  final bool inscriptionPossible;
  final CourseAccess access;

  factory Course.fromJson(dynamic j) {
    final m = _m(j);
    return Course(
      id: _i(m, 'id') ?? 0,
      titre: _s(m, 'titre') ?? '',
      description: _s(m, 'description') ?? '',
      image: _s(m, 'image'),
      prix: _s(m, 'prix') ?? '0',
      estPayant: _b(m, 'est_payant'),
      duree: _i(m, 'duree') ?? 0,
      categorie: _s(_m(m['categorie']), 'nom'),
      niveau: _s(_m(m['niveau']), 'label'),
      inscriptionPossible: _b(m, 'inscription_possible'),
      access: CourseAccess.fromJson(m['access']),
    );
  }

  String get prixLabel {
    if (!estPayant) return tr('Gratuit');
    final n = double.tryParse(prix);
    return n == null ? prix : '${n.toStringAsFixed(n % 1 == 0 ? 0 : 2)} HTG';
  }
}

class Prerequisite {
  Prerequisite(this.courseId, this.titre, this.obligatoire, this.completed);
  final int courseId;
  final String titre;
  final bool obligatoire;
  final bool completed;
}

class CourseDetail {
  CourseDetail(this.course, this.unitesCount, this.flashcardsCount,
      this.quizzesCount, this.prerequisites);
  final Course course;
  final int unitesCount, flashcardsCount, quizzesCount;
  final List<Prerequisite> prerequisites;

  factory CourseDetail.fromJson(dynamic j) {
    final m = _m(j);
    return CourseDetail(
      Course.fromJson(m),
      _i(m, 'unites_count') ?? 0,
      _i(m, 'flashcards_count') ?? 0,
      _i(m, 'quizzes_count') ?? 0,
      _l(m['prerequisites'])
          .map((p) => Prerequisite(_i(_m(p), 'course_id') ?? 0,
              _s(_m(p), 'titre') ?? '', _b(_m(p), 'obligatoire'), _b(_m(p), 'completed')))
          .toList(),
    );
  }
}

class LessonRef {
  LessonRef(this.id, this.titre, this.description);
  final int id;
  final String titre, description;
}

class ModuleOutline {
  ModuleOutline(this.id, this.titre, this.lecons);
  final int id;
  final String titre;
  final List<LessonRef> lecons;
}

class UniteOutline {
  UniteOutline(this.titre, this.modules);
  final String titre;
  final List<ModuleOutline> modules;
}

class Curriculum {
  Curriculum(this.courseId, this.unites);
  final int courseId;
  final List<UniteOutline> unites;
  List<LessonRef> get allLessons => [
        for (final u in unites)
          for (final m in u.modules) ...m.lecons,
      ];

  factory Curriculum.fromJson(dynamic j) {
    final m = _m(j);
    return Curriculum(
      _i(m, 'course_id') ?? 0,
      _l(m['unites'])
          .map((u) => UniteOutline(
                _s(_m(u), 'titre') ?? '',
                _l(_m(u)['modules'])
                    .map((mo) => ModuleOutline(
                          _i(_m(mo), 'id') ?? 0,
                          _s(_m(mo), 'titre') ?? '',
                          _l(_m(mo)['lecons'])
                              .map((le) => LessonRef(_i(_m(le), 'id') ?? 0,
                                  _s(_m(le), 'titre') ?? '', _s(_m(le), 'description') ?? ''))
                              .toList(),
                        ))
                    .toList(),
              ))
          .toList(),
    );
  }
}

class LessonContent {
  LessonContent(this.id, this.type, this.titre, this.texte, this.videoUrl,
      this.imageUrl, this.audioUrl, this.pdfUrl, this.lienUrl);
  final int id;
  final String type; // texte|video|audio|image|pdf|fichier|lien
  final String? titre, texte, videoUrl, imageUrl, audioUrl, pdfUrl, lienUrl;

  /// URL principale de la ressource selon le type.
  String? get mainUrl => switch (type) {
        'video' => videoUrl,
        'audio' => audioUrl,
        'image' => imageUrl,
        'pdf' => pdfUrl,
        'lien' => lienUrl,
        _ => pdfUrl ?? audioUrl ?? videoUrl ?? imageUrl ?? lienUrl,
      };
}

class LessonSection {
  LessonSection(this.titre, this.type, this.contenus);
  final String titre, type;
  final List<LessonContent> contenus;
}

class Lesson {
  Lesson(this.id, this.courseId, this.titre, this.description, this.contenu, this.sections);
  final int id, courseId;
  final String titre, description, contenu;
  final List<LessonSection> sections;

  factory Lesson.fromJson(dynamic j) {
    final root = _m(j);
    final m = _m(root['lesson']);
    return Lesson(
      _i(m, 'id') ?? 0,
      _i(root, 'course_id') ?? 0,
      _s(m, 'titre') ?? '',
      _s(m, 'description') ?? '',
      _s(m, 'contenu') ?? '',
      _l(m['sections'])
          .map((s) => LessonSection(
                _s(_m(s), 'titre') ?? '',
                _s(_m(s), 'type_section') ?? 'autre',
                _l(_m(s)['contenus'])
                    .map((c) => LessonContent(
                          _i(_m(c), 'id') ?? 0,
                          _s(_m(c), 'type_contenu') ?? 'texte',
                          _s(_m(c), 'titre'),
                          _s(_m(c), 'texte'),
                          _s(_m(c), 'video_url'),
                          _s(_m(c), 'image_url'),
                          _s(_m(c), 'audio_url'),
                          _s(_m(c), 'pdf_url'),
                          _s(_m(c), 'lien_url'),
                        ))
                    .toList(),
              ))
          .toList(),
    );
  }
}

class CoursePage {
  CoursePage(this.count, this.hasNext, this.results);
  final int count;
  final bool hasNext;
  final List<Course> results;
  factory CoursePage.fromJson(dynamic j) {
    final m = _m(j);
    return CoursePage(_i(m, 'count') ?? 0, m['next'] != null,
        _l(m['results']).map(Course.fromJson).toList());
  }
}

/// Résultat + indicateur « données lues depuis le cache local ».
class Loaded<T> {
  Loaded(this.value, {this.fromCache = false});
  final T value;
  final bool fromCache;
}

class Flashcard {
  Flashcard(this.id, this.question, this.reponse);
  final int id;
  final String question, reponse;

  /// Choisit le texte créole si la langue de l'app est le kreyòl et qu'il existe.
  static String _pick(Map m, String fr, String ht) {
    final h = m[ht] is String ? (m[ht] as String).trim() : '';
    final f = m[fr] is String ? m[fr] as String : '';
    return Lang.instance.isHt && h.isNotEmpty ? h : f;
  }

  static List<Flashcard> fromList(dynamic list) => _l(list)
      .map((f) => Flashcard(_i(_m(f), 'id') ?? 0, _pick(_m(f), 'question', 'question_ht'),
          _pick(_m(f), 'reponse', 'reponse_ht')))
      .toList();

  /// Réponse de `GET modules/<id>/flashcards/`.
  static List<Flashcard> listFromJson(dynamic j) => fromList(_m(j)['flashcards']);
}

class ModuleFlashcardCount {
  ModuleFlashcardCount(this.moduleId, this.titre, this.count);
  final int moduleId, count;
  final String titre;
}

/// Réponse de `GET courses/<id>/flashcards/` : anciennes flashcards « générales » du cours
/// + nombre de flashcards par module.
class CourseFlashcards {
  CourseFlashcards(this.general, this.modules);
  final List<Flashcard> general;
  final List<ModuleFlashcardCount> modules;

  int countFor(int moduleId) {
    for (final m in modules) {
      if (m.moduleId == moduleId) return m.count;
    }
    return 0;
  }

  factory CourseFlashcards.fromJson(dynamic j) {
    final m = _m(j);
    return CourseFlashcards(
      Flashcard.fromList(m['general'] ?? m['flashcards']),
      _l(m['modules'])
          .map((x) => ModuleFlashcardCount(
              _i(_m(x), 'module_id') ?? 0, _s(_m(x), 'titre') ?? '', _i(_m(x), 'count') ?? 0))
          .toList(),
    );
  }
}

class ProgressSummary {
  ProgressSummary(this.lessonsDone, this.coursePct);
  final int lessonsDone;
  final Map<int, double> coursePct; // course_id -> pourcentage
  factory ProgressSummary.fromJson(dynamic j) {
    final m = _m(j);
    final pct = <int, double>{};
    for (final c in _l(m['courses'])) {
      final id = _i(_m(c), 'course_id');
      final p = _m(c)['pourcentage'];
      if (id != null && p is num) pct[id] = p.toDouble();
    }
    return ProgressSummary(_l(m['lessons']).length, pct);
  }
}

class ActivityItem {
  ActivityItem(this.type, this.label, this.description, this.date);
  final String type, label, description;
  final DateTime? date;
  static List<ActivityItem> listFromJson(dynamic j) => _l(_m(j)['results'])
      .map((a) => ActivityItem(
            _s(_m(a), 'type') ?? '',
            _s(_m(a), 'label') ?? '',
            _s(_m(a), 'description') ?? '',
            DateTime.tryParse(_s(_m(a), 'date') ?? '')?.toLocal(),
          ))
      .toList();
}

String formatDate(DateTime? d) {
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

// ---------------- Quiz ----------------

class QuizSummary {
  QuizSummary(this.id, this.titre, this.description, this.niveau, this.duree,
      this.passPct, this.questions, this.compatible, this.bestScore, this.passed);
  final int id, duree, passPct, questions;
  final String titre, description, niveau;
  final bool compatible, passed;
  final double? bestScore;
  static List<QuizSummary> listFromJson(dynamic j) => _l(_m(j)['quizzes'])
      .map((q) => QuizSummary(
            _i(_m(q), 'id') ?? 0,
            _s(_m(q), 'titre') ?? '',
            _s(_m(q), 'description') ?? '',
            _s(_m(q), 'niveau') ?? 'cours',
            _i(_m(q), 'duree_quiz') ?? 15,
            _i(_m(q), 'pourcentage_reussite') ?? 70,
            _i(_m(q), 'questions_count') ?? 0,
            _b(_m(q), 'mobile_compatible'),
            _m(q)['best_score'] is num ? (_m(q)['best_score'] as num).toDouble() : null,
            _b(_m(q), 'passed'),
          ))
      .toList();
}

class QuizChoice {
  QuizChoice(this.id, this.texte);
  final int id;
  final String texte;
}

class QuizQuestion {
  QuizQuestion(this.id, this.type, this.supported, this.texte, this.points, this.image,
      this.audio, this.video, this.mediaTexte, this.choices);
  final int id, points;
  final String type, texte;
  final bool supported;
  final String? image, audio, video, mediaTexte;
  final List<QuizChoice> choices;

  bool get isChoice => type == 'single' || type == 'vrai_faux' || type == 'multiple';
  bool get isMultiple => type == 'multiple';
}

class QuizDetail {
  QuizDetail(this.id, this.titre, this.description, this.duree, this.passPct,
      this.courseId, this.compatible, this.questions);
  final int id, duree, passPct;
  final int? courseId;
  final String titre, description;
  final bool compatible;
  final List<QuizQuestion> questions;

  factory QuizDetail.fromJson(dynamic j) {
    final m = _m(j);
    return QuizDetail(
      _i(m, 'id') ?? 0,
      _s(m, 'titre') ?? '',
      _s(m, 'description') ?? '',
      _i(m, 'duree_quiz') ?? 15,
      _i(m, 'pourcentage_reussite') ?? 70,
      _i(m, 'course_id'),
      _b(m, 'mobile_compatible'),
      _l(m['questions']).map((q) {
        final qm = _m(q);
        final media = _m(qm['media']);
        return QuizQuestion(
          _i(qm, 'id') ?? 0,
          _s(qm, 'type') ?? '',
          _b(qm, 'supported'),
          _s(qm, 'texte') ?? '',
          _i(qm, 'points') ?? 1,
          _s(media, 'image'),
          _s(media, 'audio'),
          _s(media, 'video'),
          _s(media, 'texte'),
          _l(qm['reponses'])
              .map((r) => QuizChoice(_i(_m(r), 'id') ?? 0, _s(_m(r), 'texte') ?? ''))
              .toList(),
        );
      }).toList(),
    );
  }
}

class QuizAttempt {
  QuizAttempt(this.attemptId, this.quizId, this.expiresAt, this.resumed);
  final int attemptId, quizId;
  final DateTime? expiresAt;
  final bool resumed;
  factory QuizAttempt.fromJson(dynamic j) {
    final m = _m(j);
    return QuizAttempt(_i(m, 'attempt_id') ?? 0, _i(m, 'quiz_id') ?? 0,
        DateTime.tryParse(_s(m, 'expires_at') ?? '')?.toLocal(), _b(m, 'resumed'));
  }
}

class QuestionResult {
  QuestionResult(this.questionId, this.correct, this.explication);
  final int questionId;
  final bool? correct; // null = correction manuelle
  final String? explication;
}

class QuizResult {
  QuizResult(this.attemptId, this.quizId, this.submitted, this.score, this.reussi,
      this.passPct, this.details);
  final int attemptId, quizId, passPct;
  final bool submitted;
  final double? score;
  final bool? reussi;
  final List<QuestionResult> details;

  factory QuizResult.fromJson(dynamic j) {
    final m = _m(j);
    return QuizResult(
      _i(m, 'attempt_id') ?? 0,
      _i(m, 'quiz_id') ?? 0,
      _b(m, 'submitted'),
      m['score'] is num ? (m['score'] as num).toDouble() : null,
      m['reussi'] is bool ? m['reussi'] as bool : null,
      _i(m, 'pourcentage_reussite') ?? 70,
      _l(m['details'])
          .map((d) => QuestionResult(_i(_m(d), 'question_id') ?? 0,
              _m(d)['correct'] is bool ? _m(d)['correct'] as bool : null, _s(_m(d), 'explication')))
          .toList(),
    );
  }
}

/// Contexte passé à l'écran de passage du quiz.
class QuizRun {
  QuizRun(this.quiz, this.attempt);
  final QuizDetail quiz;
  final QuizAttempt attempt;
}
