"""
Serializers pou Flutter. Yo li done modèl ki deja egziste yo (pa gen modèl nouvo).

Konvansyon JSON:
  * Non chan yo swiv non chan modèl Django yo (titre, prix, ordre, ...).
  * Chan ki gen vèsyon FR/HT: `titre` ak `description` = vèsyon nan lang aktif
    (header Accept-Language: fr | ht, menm mekanis ak sit la), anplis
    `titre_fr` / `titre_ht` brit pou aplikasyon an ka chwazi li menm.
  * `prix` soti kòm string desimal ("1500.00") pou evite pwoblèm flotan.
  * Dat an ISO 8601.
"""
from django.utils import timezone
from rest_framework import serializers

from accounts.models import CustomUser
from courses.models import Course, Lecon, Module, Unite, SectionLecon, Contenu
from subscriptions.models import Subscription

from .access import get_course_access


# ============================================
# ITILIZATÈ
# ============================================
class UserSerializer(serializers.ModelSerializer):
    """Done pwòp kont itilizatè ki konekte a (li sèlman, pa gen modifikasyon)."""

    full_name = serializers.SerializerMethodField()
    active_subscriptions = serializers.SerializerMethodField()

    class Meta:
        model = CustomUser
        fields = [
            "id",
            "user_id",
            "email",
            "first_name",
            "last_name",
            "full_name",
            "birth_year",
            "phone_number",
            "receive_email_notifications",
            "receive_sms_notifications",
            "is_staff",
            "date_joined",
            "active_subscriptions",
        ]
        read_only_fields = fields

    def get_full_name(self, obj):
        return obj.get_full_name()

    def get_active_subscriptions(self, obj):
        subs = (
            Subscription.objects.filter(
                utilisateur=obj, statut="active", date_fin__gt=timezone.now()
            )
            .select_related("plan")
            .order_by("date_fin")
        )
        return [
            {
                "id": s.pk,
                "plan_id": s.plan_id,
                "plan_nom": s.plan.nom,
                "date_fin": s.date_fin,
                "jours_restants": s.jours_restants(),
            }
            for s in subs
        ]


class LoginSerializer(serializers.Serializer):
    # Menm jan ak fòm login sit la: `username` = email OUBYEN user_id (ex: PM04-A1B2C3)
    username = serializers.CharField(max_length=254)
    password = serializers.CharField(
        write_only=True, trim_whitespace=False, max_length=128
    )


# ============================================
# KOU
# ============================================
class CourseListSerializer(serializers.ModelSerializer):
    titre = serializers.SerializerMethodField()
    titre_fr = serializers.CharField(source="titre", read_only=True)
    titre_ht = serializers.CharField(read_only=True)
    description = serializers.SerializerMethodField()
    image = serializers.SerializerMethodField()
    est_payant = serializers.BooleanField(read_only=True)
    inscription_possible = serializers.BooleanField(read_only=True)
    categorie = serializers.SerializerMethodField()
    niveau = serializers.SerializerMethodField()
    learning_path = serializers.SerializerMethodField()
    access = serializers.SerializerMethodField()

    class Meta:
        model = Course
        fields = [
            "id",
            "titre",
            "titre_fr",
            "titre_ht",
            "description",
            "image",
            "prix",
            "est_payant",
            "duree",
            "categorie",
            "niveau",
            "learning_path",
            "position",
            "inscription_possible",
            "updated_at",
            "access",
        ]
        read_only_fields = fields

    def get_titre(self, obj):
        return obj.get_titre()

    def get_description(self, obj):
        return obj.get_description()

    def get_image(self, obj):
        url = obj.get_image()
        if not url:
            return None
        request = self.context.get("request")
        if request is not None and url.startswith("/"):
            return request.build_absolute_uri(url)
        return url

    def get_categorie(self, obj):
        if not obj.categorie_id:
            return None
        return {"id": obj.categorie_id, "nom": obj.categorie.nom}

    def get_niveau(self, obj):
        if not obj.nivo_id:
            return None
        return {
            "id": obj.nivo_id,
            "code": obj.nivo.nom,
            "label": obj.nivo.get_nom_display(),
        }

    def get_learning_path(self, obj):
        if not obj.learning_path_id:
            return None
        return {"id": obj.learning_path_id, "nom": obj.learning_path.nom}

    def get_access(self, obj):
        access_map = self.context.get("access_map")
        if access_map is not None and obj.pk in access_map:
            return access_map[obj.pk]
        request = self.context.get("request")
        return get_course_access(getattr(request, "user", None), obj)


class CourseDetailSerializer(CourseListSerializer):
    description_fr = serializers.CharField(source="description", read_only=True)
    description_ht = serializers.CharField(read_only=True)
    unites_count = serializers.SerializerMethodField()
    flashcards_count = serializers.SerializerMethodField()
    quizzes_count = serializers.SerializerMethodField()
    prerequisites = serializers.SerializerMethodField()
    prerequisites_completed = serializers.SerializerMethodField()
    previous_course_id = serializers.SerializerMethodField()
    next_course_id = serializers.SerializerMethodField()

    class Meta(CourseListSerializer.Meta):
        fields = CourseListSerializer.Meta.fields + [
            "description_fr",
            "description_ht",
            "created_at",
            "unites_count",
            "flashcards_count",
            "quizzes_count",
            "prerequisites",
            "prerequisites_completed",
            "previous_course_id",
            "next_course_id",
        ]
        read_only_fields = fields

    def get_unites_count(self, obj):
        return obj.unites.filter(actif=True).count()

    def get_flashcards_count(self, obj):
        return obj.flashcards.filter(actif=True).count()

    def get_quizzes_count(self, obj):
        return obj.quiz.filter(publie=True).count()

    def _prereq_state(self, obj):
        cache = self.context.setdefault("_prereq_cache", {})
        if obj.pk not in cache:
            user = self.context["request"].user
            cache[obj.pk] = obj.get_prerequisites_completed(user)
        return cache[obj.pk]

    def get_prerequisites(self, obj):
        _, missing = self._prereq_state(obj)
        missing_ids = {c.pk for c in missing}
        return [
            {
                "course_id": p.prerequis_id,
                "titre": p.prerequis.get_titre(),
                "obligatoire": p.obligatoire,
                "completed": p.prerequis_id not in missing_ids,
            }
            for p in obj.get_prerequisites()
        ]

    def get_prerequisites_completed(self, obj):
        ok, _ = self._prereq_state(obj)
        return ok

    def get_previous_course_id(self, obj):
        previous = obj.get_previous_course()
        return previous.pk if previous else None

    def get_next_course_id(self, obj):
        nxt = obj.get_next_course()
        return nxt.pk if nxt else None


# ============================================
# KARIKILÒM (Unite -> Module -> Lecon) — SÈLMAN STRIKTI, PA KONTNI
# ============================================
class LeconOutlineSerializer(serializers.ModelSerializer):
    titre = serializers.SerializerMethodField()
    titre_fr = serializers.CharField(source="titre", read_only=True)
    titre_ht = serializers.CharField(read_only=True)
    description = serializers.SerializerMethodField()

    class Meta:
        model = Lecon
        fields = ["id", "titre", "titre_fr", "titre_ht", "description", "ordre"]
        read_only_fields = fields

    def get_titre(self, obj):
        return obj.get_titre()

    def get_description(self, obj):
        return obj.get_description()


class ModuleOutlineSerializer(serializers.ModelSerializer):
    # `lecons_actives` vini nan Prefetch(to_attr=...) nan view la (sèlman lecon actif)
    lecons = LeconOutlineSerializer(source="lecons_actives", many=True, read_only=True)

    class Meta:
        model = Module
        fields = ["id", "titre", "description", "ordre", "lecons"]
        read_only_fields = fields


class UniteOutlineSerializer(serializers.ModelSerializer):
    # `modules_actifs` vini nan Prefetch(to_attr=...) nan view la (sèlman modul actif)
    modules = ModuleOutlineSerializer(source="modules_actifs", many=True, read_only=True)

    class Meta:
        model = Unite
        fields = ["id", "titre", "description", "ordre", "modules"]
        read_only_fields = fields


# ============================================
# KONTNI LESON POU FLUTTER
# ============================================
class MobileContentSerializer(serializers.ModelSerializer):
    """Kontni yon seksyon, ak tradiksyon selon Accept-Language."""
    titre = serializers.SerializerMethodField()
    texte = serializers.SerializerMethodField()
    video_url = serializers.SerializerMethodField()
    image_url = serializers.SerializerMethodField()
    audio_url = serializers.SerializerMethodField()
    pdf_url = serializers.SerializerMethodField()
    lien_url = serializers.SerializerMethodField()

    class Meta:
        model = Contenu
        fields = [
            "id",
            "type_contenu",
            "titre",
            "texte",
            "video_url",
            "image_url",
            "audio_url",
            "pdf_url",
            "lien_url",
            "ordre",
        ]
        read_only_fields = fields

    def _absolute_url(self, value):
        if not value:
            return None
        request = self.context.get("request")
        if request is not None and value.startswith("/"):
            return request.build_absolute_uri(value)
        return value

    def get_titre(self, obj):
        return obj.get_titre()

    def get_texte(self, obj):
        return obj.get_texte()

    def get_video_url(self, obj):
        return self._absolute_url(obj.get_video_url())

    def get_image_url(self, obj):
        return self._absolute_url(obj.get_image_url())

    def get_audio_url(self, obj):
        return self._absolute_url(obj.get_audio_url())

    def get_pdf_url(self, obj):
        return self._absolute_url(obj.get_pdf_url())

    def get_lien_url(self, obj):
        return self._absolute_url(obj.get_lien_url())


class MobileSectionSerializer(serializers.ModelSerializer):
    contenus = MobileContentSerializer(many=True, read_only=True)

    class Meta:
        model = SectionLecon
        fields = ["id", "titre", "type_section", "ordre", "contenus"]
        read_only_fields = fields


class MobileLessonDetailSerializer(serializers.ModelSerializer):
    titre = serializers.SerializerMethodField()
    titre_fr = serializers.CharField(source="titre", read_only=True)
    titre_ht = serializers.CharField(read_only=True)
    description = serializers.SerializerMethodField()
    sections = MobileSectionSerializer(many=True, read_only=True)

    class Meta:
        model = Lecon
        fields = [
            "id",
            "titre",
            "titre_fr",
            "titre_ht",
            "description",
            "contenu",
            "ordre",
            "sections",
        ]
        read_only_fields = fields

    def get_titre(self, obj):
        return obj.get_titre()

    def get_description(self, obj):
        return obj.get_description()
