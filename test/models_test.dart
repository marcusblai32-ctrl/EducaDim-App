import 'package:educadim/features/courses/models.dart';
import 'package:flutter_test/flutter_test.dart';

// Exemples tirés de mobile_api/README.md du backend.
void main() {
  test('Course.fromJson : liste', () {
    final p = CoursePage.fromJson({
      'count': 1,
      'next': null,
      'results': [
        {
          'id': 3,
          'titre': 'Cours payant',
          'description': 'd',
          'image': 'https://x/a.jpg',
          'prix': '1500.00',
          'est_payant': true,
          'duree': 12,
          'categorie': {'id': 1, 'nom': 'Langues'},
          'niveau': {'id': 1, 'code': 'debutant', 'label': 'Débutant'},
          'inscription_possible': true,
          'access': {
            'has_access': false,
            'source': null,
            'enrollment_status': 'pending',
            'expires_at': null
          },
        }
      ],
    });
    final c = p.results.single;
    expect(p.hasNext, false);
    expect(c.titre, 'Cours payant');
    expect(c.categorie, 'Langues');
    expect(c.niveau, 'Débutant');
    expect(c.access.hasAccess, false);
    expect(c.access.enrollmentStatus, 'pending');
    expect(c.prixLabel, '1500 HTG');
  });

  test('Curriculum.fromJson', () {
    final cur = Curriculum.fromJson({
      'course_id': 3,
      'unites': [
        {
          'id': 1,
          'titre': 'Unité 1',
          'modules': [
            {
              'id': 1,
              'titre': 'Module 1',
              'lecons': [
                {'id': 1, 'titre': 'Leçon 1', 'description': ''},
                {'id': 2, 'titre': 'Leçon 2', 'description': ''}
              ]
            }
          ]
        }
      ]
    });
    expect(cur.allLessons.map((l) => l.id), [1, 2]);
  });

  test('Lesson.fromJson : sections et contenus', () {
    final l = Lesson.fromJson({
      'course_id': 3,
      'lesson': {
        'id': 9,
        'titre': 'L',
        'description': '',
        'contenu': '',
        'sections': [
          {
            'id': 1,
            'titre': 'Intro',
            'type_section': 'introduction',
            'contenus': [
              {'id': 1, 'type_contenu': 'texte', 'texte': 'Bonjour'},
              {'id': 2, 'type_contenu': 'pdf', 'pdf_url': 'https://x/a.pdf'}
            ]
          }
        ]
      }
    });
    expect(l.courseId, 3);
    expect(l.sections.single.contenus[0].texte, 'Bonjour');
    expect(l.sections.single.contenus[1].mainUrl, 'https://x/a.pdf');
  });

  test('parsing tolérant : champs absents', () {
    final c = Course.fromJson({'id': 1});
    expect(c.titre, '');
    expect(c.access.hasAccess, false);
  });

  test('QuizDetail.fromJson : pas de champ de bonne réponse', () {
    final q = QuizDetail.fromJson({
      'id': 5,
      'titre': 'Quiz 1',
      'duree_quiz': 10,
      'pourcentage_reussite': 70,
      'course_id': 3,
      'mobile_compatible': true,
      'questions': [
        {
          'id': 1,
          'type': 'single',
          'supported': true,
          'texte': 'Q ?',
          'points': 2,
          'media': {'image': null, 'audio': null, 'video': null, 'texte': null},
          'reponses': [
            {'id': 10, 'texte': 'A'},
            {'id': 11, 'texte': 'B'}
          ]
        },
        {'id': 2, 'type': 'texte_trous', 'supported': true, 'texte': 'Trou', 'points': 1}
      ]
    });
    expect(q.questions.length, 2);
    expect(q.questions[0].isChoice, true);
    expect(q.questions[0].choices.map((c) => c.id), [10, 11]);
    expect(q.questions[1].isChoice, false);
    expect(q.courseId, 3);
  });

  test('QuizResult.fromJson', () {
    final r = QuizResult.fromJson({
      'attempt_id': 7,
      'quiz_id': 5,
      'submitted': true,
      'score': 66.6,
      'reussi': false,
      'pourcentage_reussite': 70,
      'details': [
        {'question_id': 1, 'correct': true, 'explication': 'ok'},
        {'question_id': 2, 'correct': null, 'explication': null}
      ]
    });
    expect(r.submitted, true);
    expect(r.reussi, false);
    expect(r.details[1].correct, isNull);
  });
}
