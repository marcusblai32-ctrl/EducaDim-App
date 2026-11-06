"""
Quiz mobil (modèl `quiz.*` ki egziste deja, pa gen migrasyon) :

  GET  /api/v1/courses/<id>/quizzes/         -> lis quiz pibliye kou a + pi bon nòt
  GET  /api/v1/quizzes/<id>/                 -> kesyon yo (SAN repons korèk yo)
  POST /api/v1/quizzes/<id>/start/           -> kòmanse/rekòmanse tantativ (idanpotan)
  POST /api/v1/quiz-attempts/<id>/submit/    -> soumèt + korije (idanpotan)
  GET  /api/v1/quiz-attempts/<id>/           -> rezilta yon tantativ

Règ :
  - aksè kou a obligatwa (HasCourseAccess) — vèsyon wèb la pa tcheke sa nan start_quiz
  - sèlman quiz `publie=True`
  - itilizatè a se request.user (JWT) ; yon tantativ se pou pwopriyetè li sèlman
  - nòt la kalkile sèvè-side ak `quiz.services.corriger_tentative` (menm lojik ak sit la)
  - repons yo dwe apatni a kesyon an (validasyon ki manke nan vèsyon wèb la)
  - soumisyon an reta (apre `expires_at`) aksepte (koneksyon Ayiti ka lan) men make `late: true`
Tip kesyon sipòte sou mobil : single, vrai_faux, multiple, texte_trous, texte_libre.
Lòt yo (audio/vidéo/fichye/imaj/konpreyansyon) -> `mobile_compatible: false`.
"""

from datetime import timedelta

from django.db import transaction
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from courses.models import Course
from quiz.models import Question, Quiz, Reponse, ReponseUtilisateur, TentativeQuiz
from quiz.services import corriger_tentative

from .permissions import HasCourseAccess

SUPPORTED_TYPES = {"single", "vrai_faux", "multiple", "texte_trous", "texte_libre"}
CHOICE_TYPES = {"single", "vrai_faux", "multiple"}


def _courses_for(user):
    qs = Course.objects.all()
    if not user.is_staff:
        qs = qs.filter(publie=True)
    return qs


def _abs(request, file_field, url_field):
    if file_field:
        try:
            return request.build_absolute_uri(file_field.url)
        except ValueError:
            return None
    return url_field or None


def _published_quiz_or_404(request, pk):
    quiz = get_object_or_404(
        Quiz.objects.prefetch_related("questions__reponses"), pk=pk, publie=True
    )
    course = quiz.get_cours_parent()
    if course is None:
        return quiz, None
    get_object_or_404(_courses_for(request.user), pk=course.pk)
    return quiz, course


def _compatible(quiz):
    qs = list(quiz.questions.all())
    return bool(qs) and all(q.type_question in SUPPORTED_TYPES for q in qs)


def _expires_at(attempt):
    return attempt.date_debut + timedelta(minutes=attempt.quiz.duree_quiz or 15)


def _question_correct(question, ru):
    """Miwwa lojik corriger_tentative, pou montre bon/move pa kesyon. None = koreksyon manyèl."""
    if ru is None:
        return False
    if ru.points_attribues is not None:
        return float(ru.points_attribues) >= question.points
    t = question.type_question
    if t in ("single", "vrai_faux"):
        good = question.reponses.filter(est_correcte=True).first()
        return bool(good and ru.reponses_selectionnees.filter(pk=good.pk).exists())
    if t == "multiple":
        good = set(question.reponses.filter(est_correcte=True).values_list("pk", flat=True))
        chosen = set(ru.reponses_selectionnees.values_list("pk", flat=True))
        return good == chosen
    if t == "texte_trous":
        first = question.reponses.first()
        return bool(first and ru.texte_reponse.strip().lower() == first.texte.strip().lower())
    return None


def _result_payload(attempt):
    answers = {
        ru.question_id: ru
        for ru in ReponseUtilisateur.objects.filter(tentative=attempt).prefetch_related(
            "reponses_selectionnees"
        )
    }
    details = []
    # Pa gen detay (korèk/eksplikasyon) anvan soumisyon : pa gen fuit.
    for q in (attempt.quiz.questions.all().order_by("ordre") if attempt.date_soumission else []):
        details.append(
            {
                "question_id": q.pk,
                "correct": _question_correct(q, answers.get(q.pk)),
                "explication": q.explication or None,
            }
        )
    return {
        "attempt_id": attempt.pk,
        "quiz_id": attempt.quiz_id,
        "submitted": attempt.date_soumission is not None,
        "score": float(attempt.score) if attempt.score is not None else None,
        "reussi": attempt.reussi,
        "pourcentage_reussite": attempt.quiz.pourcentage_reussite,
        "submitted_at": attempt.date_soumission,
        "details": details,
    }


class CourseQuizzesView(APIView):
    permission_classes = [IsAuthenticated, HasCourseAccess]

    def get(self, request, pk):
        course = get_object_or_404(_courses_for(request.user), pk=pk)
        self.check_object_permissions(request, course)
        quizzes = [
            q
            for q in Quiz.objects.filter(publie=True).prefetch_related("questions")
            if q.get_cours_parent() is not None and q.get_cours_parent().pk == course.pk
        ]
        results = []
        for q in quizzes:
            mine = TentativeQuiz.objects.filter(
                utilisateur=request.user, quiz=q, date_soumission__isnull=False
            )
            best = max((float(t.score) for t in mine if t.score is not None), default=None)
            results.append(
                {
                    "id": q.pk,
                    "titre": q.titre,
                    "description": q.description,
                    "niveau": q.get_niveau(),
                    "lecon_id": q.lecon_id,
                    "module_id": q.module_id,
                    "duree_quiz": q.duree_quiz,
                    "pourcentage_reussite": q.pourcentage_reussite,
                    "questions_count": q.questions.count(),
                    "mobile_compatible": _compatible(q),
                    "best_score": best,
                    "passed": mine.filter(reussi=True).exists(),
                }
            )
        return Response({"course_id": course.pk, "quizzes": results})


class QuizDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        quiz, course = _published_quiz_or_404(request, pk)
        if course is not None:
            self.check_permissions_for_course(request, course)
        questions = []
        for q in quiz.questions.all().order_by("ordre"):
            item = {
                "id": q.pk,
                "type": q.type_question,
                "supported": q.type_question in SUPPORTED_TYPES,
                "texte": q.texte,
                "points": q.points,
                "ordre": q.ordre,
                "media": {
                    "image": _abs(request, q.q_media_image_file, q.q_media_image_url),
                    "audio": _abs(request, q.q_media_audio_file, q.q_media_audio_url),
                    "video": _abs(request, q.q_media_video_file, q.q_media_video_url),
                    "texte": q.q_media_texte or None,
                    "titre": q.q_media_titre or None,
                },
            }
            if q.type_question in CHOICE_TYPES:
                # JAMAIS est_correcte ici
                item["reponses"] = [
                    {"id": r.pk, "texte": r.texte} for r in q.reponses.all().order_by("ordre")
                ]
            questions.append(item)
        return Response(
            {
                "id": quiz.pk,
                "titre": quiz.titre,
                "description": quiz.description,
                "duree_quiz": quiz.duree_quiz,
                "pourcentage_reussite": quiz.pourcentage_reussite,
                "course_id": course.pk if course else None,
                "mobile_compatible": _compatible(quiz),
                "media": {
                    "image": _abs(request, quiz.media_image_file, quiz.media_image_url),
                    "audio": _abs(request, quiz.media_audio_file, quiz.media_audio_url),
                    "video": _abs(request, quiz.media_video_file, quiz.media_video_url),
                    "texte": quiz.media_texte or None,
                    "titre": quiz.media_titre or None,
                },
                "questions": questions,
            }
        )

    def check_permissions_for_course(self, request, course):
        HasCourseAccess().has_object_permission(request, self, course)


class QuizStartView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        quiz, course = _published_quiz_or_404(request, pk)
        if course is not None:
            HasCourseAccess().has_object_permission(request, self, course)
        if not _compatible(quiz):
            return Response(
                {
                    "detail": "Ce quiz contient des questions non prises en charge sur mobile. "
                    "Passez-le sur le site.",
                    "code": "quiz_not_mobile_compatible",
                },
                status=status.HTTP_409_CONFLICT,
            )
        with transaction.atomic():
            attempt = (
                TentativeQuiz.objects.select_for_update()
                .filter(utilisateur=request.user, quiz=quiz, date_soumission__isnull=True)
                .order_by("-date_debut")
                .first()
            )
            created = False
            if attempt is None:
                attempt = TentativeQuiz.objects.create(utilisateur=request.user, quiz=quiz)
                created = True
        return Response(
            {
                "attempt_id": attempt.pk,
                "quiz_id": quiz.pk,
                "started_at": attempt.date_debut,
                "expires_at": _expires_at(attempt),
                "resumed": not created,
            },
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


class QuizAttemptSubmitView(APIView):
    """
    Kò: {"answers": [{"question_id": 1, "reponse_ids": [3], "texte": ""}, ...]}
    Idanpotan: si tantativ la deja soumèt, retounen rezilta ki estoke a (200, already_submitted).
    """

    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        attempt = get_object_or_404(
            TentativeQuiz.objects.select_related("quiz"), pk=pk, utilisateur=request.user
        )
        course = attempt.quiz.get_cours_parent()
        if course is not None:
            HasCourseAccess().has_object_permission(request, self, course)

        answers = request.data.get("answers")
        if not isinstance(answers, list):
            return Response(
                {"detail": "Format invalide : 'answers' doit être une liste."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        with transaction.atomic():
            attempt = TentativeQuiz.objects.select_for_update().select_related("quiz").get(pk=pk)
            if attempt.date_soumission:
                payload = _result_payload(attempt)
                payload["already_submitted"] = True
                return Response(payload, status=status.HTTP_200_OK)

            questions = {q.pk: q for q in attempt.quiz.questions.all()}
            for item in answers:
                if not isinstance(item, dict):
                    continue
                q = questions.get(item.get("question_id"))
                if q is None or q.type_question not in SUPPORTED_TYPES:
                    continue
                ru, _ = ReponseUtilisateur.objects.get_or_create(tentative=attempt, question=q)
                if q.type_question in CHOICE_TYPES:
                    ids = item.get("reponse_ids") or []
                    if not isinstance(ids, list):
                        ids = []
                    if q.type_question != "multiple":
                        ids = ids[:1]
                    valid = Reponse.objects.filter(
                        pk__in=[i for i in ids if isinstance(i, int)], question=q
                    )
                    ru.reponses_selectionnees.set(valid)
                else:
                    text = item.get("texte")
                    ru.texte_reponse = text.strip()[:5000] if isinstance(text, str) else ""
                    ru.save(update_fields=["texte_reponse"])

            late = timezone.now() > _expires_at(attempt) + timedelta(minutes=2)
            corriger_tentative(attempt)
            attempt.refresh_from_db()

        payload = _result_payload(attempt)
        payload["already_submitted"] = False
        payload["late"] = late
        return Response(payload, status=status.HTTP_201_CREATED)


class QuizAttemptDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        attempt = get_object_or_404(
            TentativeQuiz.objects.select_related("quiz"), pk=pk, utilisateur=request.user
        )
        return Response(_result_payload(attempt))
