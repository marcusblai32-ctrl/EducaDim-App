"""
Administrasyon kontni (admin ak staff ki gen pèmisyon) — kreye kou, inite, modil, leson,
seksyon, kontni, quiz, kesyon. Pa gen migrasyon (modèl ki egziste deja).

  GET   /api/v1/admin/capabilities/              -> kisa itilizatè a ka ajoute
  GET   /api/v1/admin/meta/                      -> kategori + nivo
  GET   /api/v1/admin/courses/                   -> kou li ka jere
  POST  /api/v1/admin/courses/                   -> kreye kou (BWOUYON : publie=False)
  PATCH /api/v1/admin/courses/<id>/              -> {publie: bool}
  GET   /api/v1/admin/courses/<id>/tree/         -> estrikti konplè + quiz
  POST  /api/v1/admin/courses/<id>/unites/
  POST  /api/v1/admin/unites/<id>/modules/
  POST  /api/v1/admin/modules/<id>/lecons/
  POST  /api/v1/admin/lecons/<id>/sections/
  POST  /api/v1/admin/sections/<id>/contenus/
  POST  /api/v1/admin/quizzes/                   -> {niveau: cours|module|lecon, parent_id, ...}
  PATCH /api/v1/admin/quizzes/<id>/              -> {publie: bool}
  POST  /api/v1/admin/quizzes/<id>/questions/

Règ pèmisyon (sèvè-side, pa janm fè konfyans bouton aplikasyon an) :
  - superuser : tout
  - staff : dwe gen pèmisyon Django `add_<modèl>` (courses.add_course, quiz.add_quiz, ...)
  - pou ajoute anba yon kou ki egziste : superuser, OSWA `courses.change_course`, OSWA
    se kreyatè kou a (created_by) — staff pa ka modifye kou lòt moun san `change_course`
  - pibliye/depibliye : superuser oswa `courses.change_course` / `quiz.change_quiz`
"""

from decimal import Decimal, InvalidOperation

from django.core.exceptions import ValidationError
from django.core.validators import URLValidator
from django.db import transaction
from django.db.models import Max
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from courses.models import (
    Category,
    Contenu,
    Course,
    Lecon,
    Module,
    Niveau,
    SectionLecon,
    Unite,
)
from quiz.models import Question, Quiz, Reponse

PERMS = {
    "course": "courses.add_course",
    "unite": "courses.add_unite",
    "module": "courses.add_module",
    "lecon": "courses.add_lecon",
    "section": "courses.add_sectionlecon",
    "contenu": "courses.add_contenu",
    "quiz": "quiz.add_quiz",
    "question": "quiz.add_question",
}
QUESTION_TYPES = {"single", "multiple", "vrai_faux", "texte_trous", "texte_libre"}
SECTION_TYPES = {k for k, _ in SectionLecon.TYPES_SECTION}
CONTENT_TYPES = {k for k, _ in Contenu.TYPES_CONTENU}
URL_FIELD = {
    "video": "url_video",
    "audio": "url_audio",
    "image": "url_image",
    "pdf": "url_pdf",
    "lien": "url_lien",
}


def _is_superuser(u):
    return u.is_authenticated and u.is_active and u.is_superuser


def can(user, key):
    if not (user.is_authenticated and user.is_active):
        return False
    if user.is_superuser:
        return True
    return bool(user.is_staff and user.has_perm(PERMS[key]))


def _can_edit_course(user, course):
    return _is_superuser(user) or user.has_perm("courses.change_course") or course.created_by_id == user.pk


class Bad(Exception):
    def __init__(self, msg, code=400):
        self.msg, self.code = msg, code


def _err(e):
    return Response({"detail": e.msg}, status=e.code)


def _need(user, key):
    if not can(user, key):
        raise Bad("Vous n'avez pas la permission d'effectuer cette action.", 403)


def _text(data, key, required=True, max_len=255):
    v = data.get(key)
    if v is None or v == "":
        if required:
            raise Bad(f"Le champ « {key} » est obligatoire.")
        return ""
    if not isinstance(v, str):
        raise Bad(f"Le champ « {key} » est invalide.")
    v = v.strip()
    if required and not v:
        raise Bad(f"Le champ « {key} » est obligatoire.")
    if len(v) > max_len:
        raise Bad(f"Le champ « {key} » est trop long ({max_len} caractères max).")
    return v


def _int(data, key, default, lo, hi):
    v = data.get(key, default)
    try:
        v = int(v)
    except (TypeError, ValueError):
        raise Bad(f"Le champ « {key} » doit être un nombre entier.")
    if not lo <= v <= hi:
        raise Bad(f"Le champ « {key} » doit être entre {lo} et {hi}.")
    return v


def _next_order(qs):
    return (qs.aggregate(m=Max("ordre"))["m"] or 0) + 1


def _guarded(fn):
    def wrapper(self, request, *a, **k):
        try:
            return fn(self, request, *a, **k)
        except Bad as e:
            return _err(e)

    return wrapper


class CapabilitiesView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        caps = {k: can(request.user, k) for k in PERMS}
        return Response({"can_manage": any(caps.values()), "can": caps})


class MetaView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def get(self, request):
        _need(request.user, "course")
        return Response(
            {
                "categories": [{"id": c.pk, "nom": c.nom} for c in Category.objects.filter(actif=True).order_by("ordre", "nom")],
                "niveaux": [{"id": n.pk, "label": n.get_nom_display()} for n in Niveau.objects.all()],
                "section_types": [{"value": k, "label": v} for k, v in SectionLecon.TYPES_SECTION],
                "content_types": [{"value": k, "label": v} for k, v in Contenu.TYPES_CONTENU],
            }
        )


class AdminCourseListView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def get(self, request):
        _need(request.user, "course")
        qs = Course.objects.all()
        if not (_is_superuser(request.user) or request.user.has_perm("courses.change_course")):
            qs = qs.filter(created_by=request.user)
        return Response(
            {
                "courses": [
                    {
                        "id": c.pk,
                        "titre": c.titre,
                        "publie": c.publie,
                        "prix": str(c.prix),
                        "unites_count": c.unites.count(),
                    }
                    for c in qs.order_by("-created_at")[:200]
                ]
            }
        )

    @_guarded
    def post(self, request):
        _need(request.user, "course")
        d = request.data
        titre = _text(d, "titre")
        description = _text(d, "description", required=False, max_len=5000)
        try:
            prix = Decimal(str(d.get("prix", "0") or "0"))
        except InvalidOperation:
            raise Bad("Le prix est invalide.")
        if prix < 0 or prix > Decimal("999999.99"):
            raise Bad("Le prix est invalide.")
        duree = _int(d, "duree", 0, 0, 5000)
        cat = niv = None
        if d.get("categorie_id") not in (None, ""):
            cat = Category.objects.filter(pk=d.get("categorie_id")).first()
            if cat is None:
                raise Bad("Catégorie introuvable.")
        if d.get("niveau_id") not in (None, ""):
            niv = Niveau.objects.filter(pk=d.get("niveau_id")).first()
            if niv is None:
                raise Bad("Niveau introuvable.")
        c = Course.objects.create(
            titre=titre,
            description=description,
            prix=prix.quantize(Decimal("0.01")),
            duree=duree,
            categorie=cat,
            nivo=niv,
            publie=False,  # toujours brouillon à la création
            created_by=request.user,
        )
        return Response({"id": c.pk, "titre": c.titre, "publie": c.publie}, status=status.HTTP_201_CREATED)


class AdminCourseDetailView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def patch(self, request, pk):
        course = get_object_or_404(Course, pk=pk)
        if not (_is_superuser(request.user) or request.user.has_perm("courses.change_course")):
            raise Bad("Vous n'avez pas la permission de publier ce cours.", 403)
        pub = request.data.get("publie")
        if not isinstance(pub, bool):
            raise Bad("« publie » doit être vrai ou faux.")
        course.publie = pub
        course.save(update_fields=["publie", "updated_at"])
        return Response({"id": course.pk, "publie": course.publie})


class AdminCourseTreeView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def get(self, request, pk):
        course = get_object_or_404(Course, pk=pk)
        if not (can(request.user, "course") and _can_edit_course(request.user, course)):
            raise Bad("Accès refusé.", 403)
        unites = []
        for u in course.unites.all().order_by("ordre"):
            mods = []
            for m in u.modules.all().order_by("ordre"):
                lecons = []
                for l in m.lecons.all().order_by("ordre"):
                    lecons.append(
                        {
                            "id": l.pk,
                            "titre": l.titre,
                            "sections": [
                                {
                                    "id": s.pk,
                                    "titre": s.titre,
                                    "type_section": s.type_section,
                                    "contenus_count": s.contenus.count(),
                                }
                                for s in l.sections.all().order_by("ordre")
                            ],
                        }
                    )
                mods.append({"id": m.pk, "titre": m.titre, "lecons": lecons})
            unites.append({"id": u.pk, "titre": u.titre, "modules": mods})
        quizzes = []
        seen = set()
        for q in list(Quiz.objects.filter(cours=course)) + list(
            Quiz.objects.filter(module__unite__cours=course)
        ) + list(Quiz.objects.filter(lecon__module__unite__cours=course)):
            if q.pk in seen:
                continue
            seen.add(q.pk)
            quizzes.append(
                {
                    "id": q.pk,
                    "titre": q.titre,
                    "niveau": q.get_niveau(),
                    "publie": q.publie,
                    "questions_count": q.questions.count(),
                }
            )
        return Response(
            {
                "course": {"id": course.pk, "titre": course.titre, "publie": course.publie},
                "unites": unites,
                "quizzes": quizzes,
            }
        )


def _owned_course(request, course):
    if not _can_edit_course(request.user, course):
        raise Bad("Vous ne pouvez pas modifier ce cours.", 403)


class UniteCreateView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def post(self, request, pk):
        _need(request.user, "unite")
        course = get_object_or_404(Course, pk=pk)
        _owned_course(request, course)
        d = request.data
        u = Unite.objects.create(
            cours=course,
            titre=_text(d, "titre"),
            description=_text(d, "description", False, 5000),
            ordre=_next_order(course.unites),
        )
        return Response({"id": u.pk, "titre": u.titre}, status=201)


class ModuleCreateView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def post(self, request, pk):
        _need(request.user, "module")
        unite = get_object_or_404(Unite.objects.select_related("cours"), pk=pk)
        _owned_course(request, unite.cours)
        d = request.data
        m = Module.objects.create(
            unite=unite,
            titre=_text(d, "titre"),
            description=_text(d, "description", False, 5000),
            ordre=_next_order(unite.modules),
        )
        return Response({"id": m.pk, "titre": m.titre}, status=201)


class LeconCreateView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def post(self, request, pk):
        _need(request.user, "lecon")
        module = get_object_or_404(Module.objects.select_related("unite__cours"), pk=pk)
        _owned_course(request, module.unite.cours)
        d = request.data
        l = Lecon.objects.create(
            module=module,
            titre=_text(d, "titre"),
            description=_text(d, "description", False, 5000),
            contenu=_text(d, "contenu", False, 50000),
            ordre=_next_order(module.lecons),
        )
        return Response({"id": l.pk, "titre": l.titre}, status=201)


class SectionCreateView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def post(self, request, pk):
        _need(request.user, "section")
        lecon = get_object_or_404(Lecon.objects.select_related("module__unite__cours"), pk=pk)
        _owned_course(request, lecon.module.unite.cours)
        d = request.data
        t = d.get("type_section") or "developpement"
        if t not in SECTION_TYPES:
            raise Bad("Type de section invalide.")
        s = SectionLecon.objects.create(
            lecon=lecon,
            titre=_text(d, "titre"),
            type_section=t,
            ordre=_next_order(lecon.sections),
        )
        return Response({"id": s.pk, "titre": s.titre}, status=201)


class ContenuCreateView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def post(self, request, pk):
        _need(request.user, "contenu")
        section = get_object_or_404(SectionLecon.objects.select_related("lecon__module__unite__cours"), pk=pk)
        _owned_course(request, section.lecon.module.unite.cours)
        d = request.data
        t = d.get("type_contenu")
        if t not in CONTENT_TYPES:
            raise Bad("Type de contenu invalide.")
        kwargs = {"section": section, "type_contenu": t, "titre": _text(d, "titre", False),
                  "ordre": _next_order(section.contenus)}
        if t == "texte":
            kwargs["texte"] = _text(d, "texte", True, 50000)
        elif t in URL_FIELD:
            url = _text(d, "url", True, 500)
            try:
                URLValidator(schemes=["http", "https"])(url)
            except ValidationError:
                raise Bad("L'URL est invalide (http ou https).")
            kwargs[URL_FIELD[t]] = url
        else:
            raise Bad("Les fichiers à téléverser se gèrent sur le site (type « fichier »).")
        c = Contenu.objects.create(**kwargs)
        return Response({"id": c.pk}, status=201)


class QuizCreateView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def post(self, request):
        _need(request.user, "quiz")
        d = request.data
        niveau = d.get("niveau")
        pid = d.get("parent_id")
        if niveau == "cours":
            parent = get_object_or_404(Course, pk=pid)
            course, field = parent, "cours"
        elif niveau == "module":
            parent = get_object_or_404(Module.objects.select_related("unite__cours"), pk=pid)
            course, field = parent.unite.cours, "module"
        elif niveau == "lecon":
            parent = get_object_or_404(Lecon.objects.select_related("module__unite__cours"), pk=pid)
            course, field = parent.module.unite.cours, "lecon"
        else:
            raise Bad("Niveau de quiz invalide (cours, module ou lecon).")
        _owned_course(request, course)
        q = Quiz.objects.create(
            **{field: parent},
            titre=_text(d, "titre", True, 200),
            description=_text(d, "description", False, 5000),
            pourcentage_reussite=_int(d, "pourcentage_reussite", 70, 1, 100),
            duree_quiz=_int(d, "duree_quiz", 15, 1, 600),
            publie=False,  # brouillon tant qu'il n'a pas de questions
        )
        return Response({"id": q.pk, "titre": q.titre, "publie": q.publie}, status=201)


def _quiz_course(q):
    return q.get_cours_parent()


class QuizDetailAdminView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def patch(self, request, pk):
        q = get_object_or_404(Quiz, pk=pk)
        if not (_is_superuser(request.user) or request.user.has_perm("quiz.change_quiz")):
            raise Bad("Vous n'avez pas la permission de publier ce quiz.", 403)
        pub = request.data.get("publie")
        if not isinstance(pub, bool):
            raise Bad("« publie » doit être vrai ou faux.")
        if pub and not q.questions.exists():
            raise Bad("Ajoutez au moins une question avant de publier.")
        q.publie = pub
        q.save(update_fields=["publie"])
        return Response({"id": q.pk, "publie": q.publie})


class QuestionCreateView(APIView):
    permission_classes = [IsAuthenticated]

    @_guarded
    def post(self, request, pk):
        _need(request.user, "question")
        quiz = get_object_or_404(Quiz, pk=pk)
        course = _quiz_course(quiz)
        if course is not None:
            _owned_course(request, course)
        d = request.data
        t = d.get("type_question")
        if t not in QUESTION_TYPES:
            raise Bad("Type de question non pris en charge (single, multiple, vrai_faux, texte_trous, texte_libre).")
        texte = _text(d, "texte", True, 5000)
        points = _int(d, "points", 1, 1, 100)
        explication = _text(d, "explication", False, 5000)
        answers = d.get("reponses") or []
        if not isinstance(answers, list):
            raise Bad("« reponses » doit être une liste.")
        clean = []
        for a in answers:
            if not isinstance(a, dict):
                continue
            tx = (a.get("texte") or "").strip() if isinstance(a.get("texte"), str) else ""
            if tx:
                clean.append((tx[:500], a.get("est_correcte") is True))

        if t == "vrai_faux":
            good = d.get("vrai_est_correct")
            if not isinstance(good, bool):
                raise Bad("Indiquez si la bonne réponse est « Vrai » ou « Faux ».")
            clean = [("Vrai", good), ("Faux", not good)]
        elif t == "single":
            if len(clean) < 2 or sum(1 for _, c in clean if c) != 1:
                raise Bad("Choix unique : au moins 2 réponses dont exactement 1 correcte.")
        elif t == "multiple":
            if len(clean) < 2 or not any(c for _, c in clean):
                raise Bad("Choix multiples : au moins 2 réponses dont au moins 1 correcte.")
        elif t == "texte_trous":
            if not clean:
                raise Bad("Indiquez le texte attendu.")
            clean = [(clean[0][0], True)]
        else:  # texte_libre
            clean = []

        with transaction.atomic():
            q = Question.objects.create(
                quiz=quiz,
                type_question=t,
                texte=texte,
                points=points,
                explication=explication,
                ordre=_next_order(quiz.questions),
            )
            for i, (tx, ok) in enumerate(clean, start=1):
                Reponse.objects.create(question=q, texte=tx, est_correcte=ok, ordre=i)
        return Response({"id": q.pk, "questions_count": quiz.questions.count()}, status=201)
