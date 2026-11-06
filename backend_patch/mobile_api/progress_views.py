"""
Endpoints mobil adisyonèl (pa modifye views.py ki egziste deja) :

  POST /api/v1/lessons/<id>/complete/   -> mache yon leson kòm fini (idanpotan)
  GET  /api/v1/me/progress/             -> pwogrè itilizatè a (pou sinkwonize Flutter)
  GET  /api/v1/me/activity/             -> 30 dènye aktivite itilizatè a
  GET  /api/v1/courses/<id>/flashcards/ -> flashcards kou a (kontni pwoteje)

Menm règ ak sit la (progress.views.mark_lecon_complete) :
  - aksè kou a obligatwa (HasCourseAccess)
  - quiz pibliye ki lye ak leson an dwe reyisi anvan
  - tout lojik fini pase pa ProgresLecon.terminer()
Itilizatè a se toujou request.user (JWT), pa janm yon ID voye pa kliyan an.
"""

from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from courses.models import Course, Flashcard, Lecon
from progress.models import ActiviteUtilisateur, ProgresCours, ProgresLecon
from quiz.models import TentativeQuiz

from .permissions import HasCourseAccess


def _published_courses_for(user):
    qs = Course.objects.all()
    if not user.is_staff:
        qs = qs.filter(publie=True)
    return qs


class LessonCompleteView(APIView):
    """
    POST /api/v1/lessons/<id>/complete/
    Kò opsyonèl: {"client_id": "...", "completed_at": "..."} (ignore pou kounye a ;
    dat la se lè sèvè a). Repons 200 si leson an te deja fini (idanpotan), 201 si
    li fèk fini kounye a. 403 `lesson_quiz_required` si quiz la pa reyisi.
    """

    permission_classes = [IsAuthenticated, HasCourseAccess]

    def post(self, request, pk):
        lesson = get_object_or_404(
            Lecon.objects.select_related("module__unite__cours").prefetch_related("quiz"),
            pk=pk,
            actif=True,
        )
        course = lesson.module.unite.cours
        get_object_or_404(_published_courses_for(request.user), pk=course.pk)
        self.check_object_permissions(request, course)

        required = lesson.quiz.filter(publie=True)
        if required.exists():
            passed = TentativeQuiz.objects.filter(
                utilisateur=request.user, quiz__in=required, reussi=True
            ).exists()
            if not passed:
                return Response(
                    {
                        "detail": "Vous devez réussir le quiz avant de terminer cette leçon.",
                        "code": "lesson_quiz_required",
                        "quiz_ids": list(required.values_list("id", flat=True)),
                    },
                    status=status.HTTP_403_FORBIDDEN,
                )

        with transaction.atomic():
            progres, _ = ProgresLecon.objects.select_for_update().get_or_create(
                utilisateur=request.user, lecon=lesson
            )
            already = progres.est_termine()
            if not already:
                progres.terminer()
                ActiviteUtilisateur.objects.create(
                    utilisateur=request.user,
                    type_activite="lecon_termine",
                    description=f"Leçon terminée: {lesson.titre}",
                    cours=course,
                    lecon=lesson,
                )

        pc = ProgresCours.objects.filter(utilisateur=request.user, cours=course).first()
        return Response(
            {
                "lesson_id": lesson.pk,
                "course_id": course.pk,
                "statut": "termine",
                "already_completed": already,
                "course_progress": float(pc.pourcentage) if pc else 0.0,
            },
            status=status.HTTP_200_OK if already else status.HTTP_201_CREATED,
        )


class MyProgressView(APIView):
    """GET /api/v1/me/progress/ — leson fini + pousantaj chak kou."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        lessons = ProgresLecon.objects.filter(
            utilisateur=request.user, statut="termine"
        ).select_related("lecon__module__unite")
        courses = ProgresCours.objects.filter(utilisateur=request.user)
        return Response(
            {
                "lessons": [
                    {
                        "lesson_id": p.lecon_id,
                        "course_id": p.lecon.module.unite.cours_id,
                        "statut": p.statut,
                        "completed_at": p.date_fin,
                    }
                    for p in lessons
                ],
                "courses": [
                    {"course_id": c.cours_id, "pourcentage": float(c.pourcentage)}
                    for c in courses
                ],
            }
        )


class MyActivityView(APIView):
    """GET /api/v1/me/activity/ — 30 dènye aktivite (leson, quiz, kou fini, badge...)."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        acts = ActiviteUtilisateur.objects.filter(utilisateur=request.user).order_by("-date")[:30]
        return Response(
            {
                "results": [
                    {
                        "id": a.pk,
                        "type": a.type_activite,
                        "label": a.get_type_activite_display(),
                        "description": a.description,
                        "course_id": a.cours_id,
                        "lesson_id": a.lecon_id,
                        "date": a.date,
                    }
                    for a in acts
                ]
            }
        )


class CourseFlashcardsView(APIView):
    """GET /api/v1/courses/<id>/flashcards/ — 403 course_access_required si pa gen aksè."""

    permission_classes = [IsAuthenticated, HasCourseAccess]

    def get(self, request, pk):
        course = get_object_or_404(_published_courses_for(request.user), pk=pk)
        self.check_object_permissions(request, course)
        cards = Flashcard.objects.filter(cours=course, actif=True).order_by("ordre", "pk")
        return Response(
            {
                "course_id": course.pk,
                "flashcards": [
                    {
                        "id": f.pk,
                        "question": f.question,
                        "question_ht": f.question_ht,
                        "reponse": f.reponse,
                        "reponse_ht": f.reponse_ht,
                        "ordre": f.ordre,
                    }
                    for f in cards
                ],
            }
        )
