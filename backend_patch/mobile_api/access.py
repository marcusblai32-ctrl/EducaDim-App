"""
Verifikasyon aksè kou pou API mobil la.

SÈLMAN LI: pa janm ekri nan baz done a (kontrèman ak course_detail sou sit la
ki kreye SubscriptionAccess ki manke). Lojik la swiv menm règ ak
courses.views._get_user_access + subscriptions.access.active_subscription_for_course :

  * Kou gratis (prix = 0)  -> aksè pou nenpòt itilizatè konekte (menm jan ak sit la).
  * Enrollment statut 'active' -> aksè.
  * Abònman aktif ki kouvri kou a -> aksè:
      - SubscriptionAccess (abònman 'active', date_expiration > kounye a), oswa
      - plan san limit (max_courses=0) ki gen kou a, oswa
      - plan ak limit kote itilizatè a te chwazi kou a (SubscriptionCourseSelection).

Pa gen okenn modèl nouvo: tout bagay li nan Enrollment, Subscription,
SubscriptionAccess ak SubscriptionCourseSelection ki deja egziste.
"""
from django.utils import timezone

from enrollments.models import Enrollment
from subscriptions.models import (
    Subscription,
    SubscriptionAccess,
    SubscriptionCourseSelection,
)

SOURCE_ENROLLMENT = "enrollment"
SOURCE_SUBSCRIPTION = "subscription"
SOURCE_FREE = "free"


def _no_access(enrollment_status=None):
    return {
        "has_access": False,
        "source": None,
        "enrollment_status": enrollment_status,
        "expires_at": None,
    }


def get_access_map(user, courses):
    """
    Retounen {course_id: {has_access, source, enrollment_status, expires_at}}
    pou yon lis kou, avèk yon kantite kèk requête fiks (pa N+1).

    `courses` = iterab Course (oswa lis objè ki gen .pk ak .est_payant).
    """
    courses = list(courses)
    if not courses:
        return {}

    paid_by_id = {c.pk: c.est_payant for c in courses}
    ids = set(paid_by_id)

    if user is None or not user.is_authenticated:
        return {cid: _no_access() for cid in ids}

    now = timezone.now()

    # 1. Enrollments (tout statut, pou ka bay enrollment_status)
    enrollment_status = dict(
        Enrollment.objects.filter(utilisateur=user, cours_id__in=ids)
        .values_list("cours_id", "statut")
    )

    # 2. SubscriptionAccess valid
    sub_expiry = {}

    def _remember(course_id, expires_at):
        # Si plizyè abònman kouvri menm kou a, kenbe dat ekspirasyon ki pi lwen an
        # (None = pa gen dat fen, kidonk li pi lwen toujou).
        if course_id not in sub_expiry:
            sub_expiry[course_id] = expires_at
            return
        previous = sub_expiry[course_id]
        if previous is None:
            return
        if expires_at is None or expires_at > previous:
            sub_expiry[course_id] = expires_at

    for cours_id, expiration in SubscriptionAccess.objects.filter(
        subscription__utilisateur=user,
        subscription__statut="active",
        cours_id__in=ids,
        date_expiration__gt=now,
    ).values_list("cours_id", "date_expiration"):
        _remember(cours_id, expiration)

    # 3. Plan san limit (max_courses=0) -> kou ki nan plan an
    for sub in Subscription.objects.filter(
        utilisateur=user,
        statut="active",
        plan__max_courses=0,
        date_fin__gt=now,
    ).select_related("plan").prefetch_related("plan__cours"):
        for course in sub.plan.cours.all():
            if course.pk in ids:
                _remember(course.pk, sub.date_fin)

    # 4. Plan ak limit -> kou itilizatè a te chwazi
    for cours_id, date_fin in SubscriptionCourseSelection.objects.filter(
        subscription__utilisateur=user,
        subscription__statut="active",
        subscription__date_fin__gt=now,
        course_id__in=ids,
    ).values_list("course_id", "subscription__date_fin"):
        _remember(cours_id, date_fin)

    result = {}
    for cid in ids:
        status = enrollment_status.get(cid)
        if status == "active":
            result[cid] = {
                "has_access": True,
                "source": SOURCE_ENROLLMENT,
                "enrollment_status": status,
                "expires_at": None,
            }
        elif cid in sub_expiry:
            result[cid] = {
                "has_access": True,
                "source": SOURCE_SUBSCRIPTION,
                "enrollment_status": status,
                "expires_at": sub_expiry[cid],
            }
        elif not paid_by_id[cid]:
            result[cid] = {
                "has_access": True,
                "source": SOURCE_FREE,
                "enrollment_status": status,
                "expires_at": None,
            }
        else:
            result[cid] = _no_access(status)
    return result


def get_course_access(user, course):
    """Aksè yon itilizatè nan yon sèl kou (menm lojik ak get_access_map)."""
    return get_access_map(user, [course])[course.pk]
