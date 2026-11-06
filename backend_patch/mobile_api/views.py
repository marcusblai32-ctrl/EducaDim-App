import logging

from django.core.exceptions import PermissionDenied
from axes.handlers.proxy import AxesProxyHandler
from django.contrib.auth import authenticate
from django.db.models import Prefetch, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.generics import GenericAPIView
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from courses.models import Course, Lecon, Module, Unite
from quiz.models import TentativeQuiz

from .access import get_access_map, get_course_access
from .permissions import HasCourseAccess
from .serializers import (
    CourseDetailSerializer,
    CourseListSerializer,
    LoginSerializer,
    MobileLessonDetailSerializer,
    UniteOutlineSerializer,
    UserSerializer,
)
from .throttles import LoginRateThrottle


logger = logging.getLogger(__name__)


# ============================================
# AUTH
# ============================================
class LoginView(APIView):
    """
    POST /api/v1/auth/login/
    Itilize menm backends ak sit la (email OUBYEN user_id + modpas), kidonk
    django-axes (blokaj apre echèk repete) aplike tou.
    """

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [LoginRateThrottle]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        username = serializer.validated_data["username"]
        password = serializer.validated_data["password"]
        django_request = request._request

        # Verifye blokaj Axes anvan nou rele lòt authentication backends yo.
        # Sa anpeche yon backend pèsonalize pase sou blokaj Axes la.
        if AxesProxyHandler.is_locked(
            django_request,
            credentials={"username": username},
        ):
            return Response(
                {
                    "detail": "Trop de tentatives échouées. Réessayez plus tard.",
                    "code": "account_locked",
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        try:
            user = authenticate(
                django_request,
                username=username,
                password=password,
            )
        except PermissionDenied:
            # django-axes: kont/IP bloke pou twòp echèk
            return Response(
                {
                    "detail": "Trop de tentatives échouées. Réessayez plus tard.",
                    "code": "account_locked",
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        if user is None or not user.is_active:
            return Response(
                {
                    "detail": "Email/ID ou mot de passe incorrect.",
                    "code": "invalid_credentials",
                },
                status=status.HTTP_401_UNAUTHORIZED,
            )

        user.update_activity()
        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "user": UserSerializer(user, context={"request": request}).data,
            }
        )


class MeView(APIView):
    """GET /api/v1/me/ — kont itilizatè ki konekte a (li sèlman)."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        # Menm règ ak UpdateActivityMiddleware: maksimòm yon ekriti chak 10 minit.
        user = request.user
        if (timezone.now() - user.last_activity).total_seconds() > 600:
            user.update_activity()
        return Response(UserSerializer(user, context={"request": request}).data)


# ============================================
# KOU
# ============================================
def _int_param(request, name):
    raw = request.query_params.get(name)
    if raw in (None, ""):
        return None
    try:
        return int(raw)
    except (TypeError, ValueError):
        raise ValidationError({name: "Doit être un entier."})


def _published_courses_for(user):
    """Kou piblye yo. Staff ka wè tou kou ki pa piblye (pou tès)."""
    qs = Course.objects.select_related("categorie", "nivo", "learning_path")
    if not user.is_staff:
        qs = qs.filter(publie=True)
    return qs


class CourseListView(GenericAPIView):
    """
    GET /api/v1/courses/
    Menm filt ak sit la: ?search= ?category= ?niveau= ?prix=gratuit|payant ?learning_path=
    Pajinasyon DRF pa default la (?page=).
    """

    permission_classes = [IsAuthenticated]
    serializer_class = CourseListSerializer

    def get_queryset(self):
        request = self.request
        qs = Course.objects.filter(publie=True).select_related(
            "categorie", "nivo", "learning_path"
        )

        search = request.query_params.get("search", "").strip()
        if search:
            qs = qs.filter(
                Q(titre__icontains=search)
                | Q(description__icontains=search)
                | Q(titre_ht__icontains=search)
                | Q(description_ht__icontains=search)
            )

        category = _int_param(request, "category")
        if category is not None:
            qs = qs.filter(categorie_id=category)

        niveau = _int_param(request, "niveau")
        if niveau is not None:
            qs = qs.filter(nivo_id=niveau)

        prix = request.query_params.get("prix")
        if prix == "gratuit":
            qs = qs.filter(prix=0)
        elif prix == "payant":
            qs = qs.filter(prix__gt=0)
        elif prix not in (None, ""):
            raise ValidationError({"prix": "Valeurs permises: gratuit, payant."})

        learning_path = _int_param(request, "learning_path")
        if learning_path is not None:
            qs = qs.filter(learning_path_id=learning_path)

        return qs

    def get(self, request):
        page = self.paginate_queryset(self.get_queryset())
        courses = page if page is not None else list(self.get_queryset())
        context = self.get_serializer_context()
        context["access_map"] = get_access_map(request.user, courses)
        data = self.get_serializer(courses, many=True, context=context).data
        if page is not None:
            return self.get_paginated_response(data)
        return Response(data)


class CourseDetailView(APIView):
    """GET /api/v1/courses/<id>/ — metadata kou + blòk `access`."""

    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        course = get_object_or_404(_published_courses_for(request.user), pk=pk)
        return Response(
            CourseDetailSerializer(course, context={"request": request}).data
        )


class CourseAccessView(APIView):
    """
    GET /api/v1/courses/<id>/access/
    Repons rapid: eske itilizatè a gen aksè? (Flutter rele sa anvan li louvri
    oswa telechaje kontni.) Pa gen 403: repons toujou 200 ak `has_access`.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        course = get_object_or_404(_published_courses_for(request.user), pk=pk)
        return Response({"course_id": course.pk, **get_course_access(request.user, course)})


class CourseCurriculumView(APIView):
    """
    GET /api/v1/courses/<id>/curriculum/
    KONTNI PWOTEJE: 403 `course_access_required` si pa gen aksè.
    Retounen sèlman estrikti (unite -> modul -> leson aktif), pa kontni leson yo.
    """

    permission_classes = [IsAuthenticated, HasCourseAccess]

    def get(self, request, pk):
        course = get_object_or_404(_published_courses_for(request.user), pk=pk)
        self.check_object_permissions(request, course)

        lecons = Prefetch(
            "lecons",
            queryset=Lecon.objects.filter(actif=True),
            to_attr="lecons_actives",
        )
        modules = Prefetch(
            "modules",
            queryset=Module.objects.filter(actif=True).prefetch_related(lecons),
            to_attr="modules_actifs",
        )
        unites = Unite.objects.filter(cours=course, actif=True).prefetch_related(modules)

        return Response(
            {
                "course_id": course.pk,
                # Pa yon vèrsyon reyèl: Course.updated_at pa chanje lè leson/kontni chanje.
                "course_updated_at": course.updated_at,
                "unites": UniteOutlineSerializer(unites, many=True).data,
            }
        )


# ============================================
# DETAY LESON — KONTNI PWOTEJE
# ============================================
class LessonDetailView(APIView):
    """
    GET /api/v1/lessons/<id>/

    Kontni leson an disponib sèlman si itilizatè a gen aksè nan kou paran an.
    Si gen quiz pibliye ki asosye dirèkteman ak leson an, itilizatè a dwe
    genyen omwen yon tantativ reyisi anvan API a voye kontni an.
    """

    permission_classes = [IsAuthenticated, HasCourseAccess]

    def get(self, request, pk):
        lesson = get_object_or_404(
            Lecon.objects.select_related(
                "module__unite__cours"
            ).prefetch_related(
                "sections__contenus",
                "quiz",
            ),
            pk=pk,
            actif=True,
        )

        course = lesson.module.unite.cours

        # Respekte menm règ piblikasyon ak lòt endpoint API mobil yo.
        get_object_or_404(
            _published_courses_for(request.user),
            pk=course.pk,
        )

        # HasCourseAccess mande yon Course kòm objè.
        self.check_object_permissions(request, course)

        # Verifye quiz pibliye ki asosye dirèkteman ak leson sa a.
        required_quizzes = lesson.quiz.filter(publie=True)

        if required_quizzes.exists():
            passed = TentativeQuiz.objects.filter(
                utilisateur=request.user,
                quiz__in=required_quizzes,
                reussi=True,
            ).exists()

            if not passed:
                return Response(
                    {
                        "detail": (
                            "Vous devez réussir le quiz avant "
                            "de consulter cette leçon."
                        ),
                        "code": "lesson_quiz_required",
                        "quiz_ids": list(
                            required_quizzes.values_list("id", flat=True)
                        ),
                    },
                    status=status.HTTP_403_FORBIDDEN,
                )

        serializer = MobileLessonDetailSerializer(
            lesson,
            context={"request": request},
        )

        return Response(
            {
                "course_id": course.pk,
                "lesson": serializer.data,
            }
        )
