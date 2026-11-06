from datetime import timedelta

from django.core.cache import cache
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import CustomUser
from courses.models import Course, Lecon, Module, Unite
from enrollments.models import Enrollment
from subscriptions.models import (
    Subscription,
    SubscriptionAccess,
    SubscriptionCourseSelection,
    SubscriptionPlan,
)

PASSWORD = "Test-password-2026!"

LOCAL_STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"
    },
}


def make_user(email, **extra):
    return CustomUser.objects.create_user(
        email=email,
        first_name="Marie",
        last_name="Pierre",
        birth_year=2000,
        password=PASSWORD,
        **extra,
    )


@override_settings(STORAGES=LOCAL_STORAGES)
class MobileApiBase(TestCase):
    def setUp(self):
        cache.clear()  # throttles yo itilize cache la
        self.client = APIClient()
        self.user = make_user("student@example.com")
        self.other = make_user("other@example.com")

        self.free = Course.objects.create(titre="Cours gratuit", publie=True, prix=0)
        self.paid = Course.objects.create(
            titre="Cours payant", titre_ht="Kou ki peye", publie=True, prix=1500
        )
        self.draft = Course.objects.create(titre="Brouillon", publie=False, prix=0)

        unite = Unite.objects.create(cours=self.paid, titre="Unité 1", ordre=1)
        Unite.objects.create(cours=self.paid, titre="Unité cachée", ordre=2, actif=False)
        module = Module.objects.create(unite=unite, titre="Module 1", ordre=1)
        Lecon.objects.create(module=module, titre="Leçon 1", titre_ht="Leson 1", ordre=1)
        Lecon.objects.create(module=module, titre="Leçon cachée", ordre=2, actif=False)

    def auth(self, user=None):
        resp = self.client.post(
            reverse("mobile_api:login"),
            {"username": (user or self.user).email, "password": PASSWORD},
            format="json",
        )
        self.assertEqual(resp.status_code, 200, resp.content)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {resp.data['access']}")
        return resp

    def curriculum_url(self, course):
        return reverse("mobile_api:course_curriculum", args=[course.pk])


class UrlTests(MobileApiBase):
    def test_url_prefix_is_api_v1(self):
        self.assertEqual(reverse("mobile_api:login"), "/api/v1/auth/login/")
        self.assertEqual(reverse("mobile_api:token_refresh"), "/api/v1/auth/token/refresh/")
        self.assertEqual(reverse("mobile_api:me"), "/api/v1/me/")
        self.assertEqual(reverse("mobile_api:course_list"), "/api/v1/courses/")
        self.assertEqual(reverse("mobile_api:course_detail", args=[1]), "/api/v1/courses/1/")
        self.assertEqual(reverse("mobile_api:course_access", args=[1]), "/api/v1/courses/1/access/")
        self.assertEqual(
            reverse("mobile_api:course_curriculum", args=[1]),
            "/api/v1/courses/1/curriculum/",
        )


class AuthTests(MobileApiBase):
    def test_login_with_email(self):
        resp = self.auth()
        self.assertIn("refresh", resp.data)
        self.assertEqual(resp.data["user"]["email"], self.user.email)
        self.assertNotIn("password", resp.data["user"])

    def test_login_with_user_id(self):
        resp = self.client.post(
            reverse("mobile_api:login"),
            {"username": self.user.user_id, "password": PASSWORD},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)

    def test_login_wrong_password(self):
        resp = self.client.post(
            reverse("mobile_api:login"),
            {"username": self.user.email, "password": "wrong"},
            format="json",
        )
        self.assertEqual(resp.status_code, 401)
        self.assertEqual(resp.data["code"], "invalid_credentials")

    def test_login_inactive_user(self):
        self.user.is_active = False
        self.user.save()
        resp = self.client.post(
            reverse("mobile_api:login"),
            {"username": self.user.email, "password": PASSWORD},
            format="json",
        )
        self.assertEqual(resp.status_code, 401)

    def test_login_missing_fields(self):
        resp = self.client.post(reverse("mobile_api:login"), {}, format="json")
        self.assertEqual(resp.status_code, 400)

    def test_login_lockout_after_repeated_failures(self):
        for _ in range(5):
            self.client.post(
                reverse("mobile_api:login"),
                {"username": self.user.email, "password": "wrong"},
                format="json",
            )
        resp = self.client.post(
            reverse("mobile_api:login"),
            {"username": self.user.email, "password": PASSWORD},
            format="json",
        )
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(resp.data["code"], "account_locked")

    def test_refresh_returns_new_access_token(self):
        login = self.auth()
        self.client.credentials()
        resp = self.client.post(
            reverse("mobile_api:token_refresh"),
            {"refresh": login.data["refresh"]},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        self.assertIn("access", resp.data)

    def test_refresh_with_garbage_token(self):
        resp = self.client.post(
            reverse("mobile_api:token_refresh"), {"refresh": "garbage"}, format="json"
        )
        self.assertEqual(resp.status_code, 401)

    def test_me_requires_authentication(self):
        self.assertEqual(self.client.get(reverse("mobile_api:me")).status_code, 401)

    def test_me_returns_own_account_only(self):
        self.auth()
        resp = self.client.get(reverse("mobile_api:me"))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["email"], self.user.email)
        self.assertEqual(resp.data["user_id"], self.user.user_id)
        self.assertEqual(resp.data["active_subscriptions"], [])
        self.assertNotIn("password", resp.data)

    def test_me_lists_active_subscription(self):
        plan = SubscriptionPlan.objects.create(nom="Plan A", prix=500)
        Subscription.objects.create(
            utilisateur=self.user,
            plan=plan,
            statut="active",
            date_fin=timezone.now() + timedelta(days=10),
        )
        self.auth()
        resp = self.client.get(reverse("mobile_api:me"))
        self.assertEqual(len(resp.data["active_subscriptions"]), 1)
        self.assertEqual(resp.data["active_subscriptions"][0]["plan_nom"], "Plan A")


class CourseCatalogTests(MobileApiBase):
    def test_list_requires_authentication(self):
        self.assertEqual(self.client.get(reverse("mobile_api:course_list")).status_code, 401)

    def test_list_only_published(self):
        self.auth()
        resp = self.client.get(reverse("mobile_api:course_list"))
        self.assertEqual(resp.status_code, 200)
        ids = {c["id"] for c in resp.data["results"]}
        self.assertEqual(ids, {self.free.pk, self.paid.pk})

    def test_list_access_blocks(self):
        self.auth()
        resp = self.client.get(reverse("mobile_api:course_list"))
        by_id = {c["id"]: c for c in resp.data["results"]}
        self.assertTrue(by_id[self.free.pk]["access"]["has_access"])
        self.assertEqual(by_id[self.free.pk]["access"]["source"], "free")
        self.assertFalse(by_id[self.paid.pk]["access"]["has_access"])
        self.assertEqual(by_id[self.paid.pk]["prix"], "1500.00")

    def test_list_filters(self):
        self.auth()
        url = reverse("mobile_api:course_list")
        gratuit = self.client.get(url, {"prix": "gratuit"})
        self.assertEqual({c["id"] for c in gratuit.data["results"]}, {self.free.pk})
        payant = self.client.get(url, {"prix": "payant"})
        self.assertEqual({c["id"] for c in payant.data["results"]}, {self.paid.pk})
        search = self.client.get(url, {"search": "payant"})
        self.assertEqual({c["id"] for c in search.data["results"]}, {self.paid.pk})

    def test_list_invalid_filters_return_400(self):
        self.auth()
        url = reverse("mobile_api:course_list")
        self.assertEqual(self.client.get(url, {"category": "abc"}).status_code, 400)
        self.assertEqual(self.client.get(url, {"prix": "xyz"}).status_code, 400)

    def test_list_language_header(self):
        self.auth()
        url = reverse("mobile_api:course_list")
        resp = self.client.get(url, HTTP_ACCEPT_LANGUAGE="ht")
        by_id = {c["id"]: c for c in resp.data["results"]}
        self.assertEqual(by_id[self.paid.pk]["titre_fr"], "Cours payant")
        self.assertEqual(by_id[self.paid.pk]["titre_ht"], "Kou ki peye")

    def test_detail_published(self):
        self.auth()
        resp = self.client.get(reverse("mobile_api:course_detail", args=[self.paid.pk]))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["id"], self.paid.pk)
        self.assertEqual(resp.data["unites_count"], 1)
        self.assertFalse(resp.data["access"]["has_access"])

    def test_detail_unpublished_is_404(self):
        self.auth()
        resp = self.client.get(reverse("mobile_api:course_detail", args=[self.draft.pk]))
        self.assertEqual(resp.status_code, 404)

    def test_detail_requires_authentication(self):
        resp = self.client.get(reverse("mobile_api:course_detail", args=[self.free.pk]))
        self.assertEqual(resp.status_code, 401)


class CourseProtectionTests(MobileApiBase):
    def test_curriculum_requires_authentication(self):
        self.assertEqual(self.client.get(self.curriculum_url(self.paid)).status_code, 401)

    def test_paid_course_without_access_is_403(self):
        self.auth()
        resp = self.client.get(self.curriculum_url(self.paid))
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(resp.data["code"], "course_access_required")
        self.assertEqual(resp.data["course_id"], self.paid.pk)
        self.assertNotIn("unites", resp.data)

    def test_pending_enrollment_is_not_access(self):
        Enrollment.objects.create(utilisateur=self.user, cours=self.paid, statut="pending")
        self.auth()
        resp = self.client.get(self.curriculum_url(self.paid))
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(resp.data["enrollment_status"], "pending")

    def test_rejected_and_cancelled_enrollment_are_not_access(self):
        Enrollment.objects.create(utilisateur=self.user, cours=self.paid, statut="rejected")
        self.auth()
        self.assertEqual(self.client.get(self.curriculum_url(self.paid)).status_code, 403)

    def test_active_enrollment_gives_access_and_filters_inactive(self):
        Enrollment.objects.create(utilisateur=self.user, cours=self.paid, statut="active")
        self.auth()
        resp = self.client.get(self.curriculum_url(self.paid))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data["unites"]), 1)
        module = resp.data["unites"][0]["modules"][0]
        self.assertEqual([l["titre"] for l in module["lecons"]], ["Leçon 1"])

    def test_other_users_enrollment_does_not_grant_access(self):
        Enrollment.objects.create(utilisateur=self.other, cours=self.paid, statut="active")
        self.auth(self.user)
        self.assertEqual(self.client.get(self.curriculum_url(self.paid)).status_code, 403)

    def test_free_course_is_accessible(self):
        self.auth()
        self.assertEqual(self.client.get(self.curriculum_url(self.free)).status_code, 200)

    def test_unpublished_course_curriculum_is_404(self):
        self.auth()
        self.assertEqual(self.client.get(self.curriculum_url(self.draft)).status_code, 404)

    def test_access_endpoint_never_403(self):
        self.auth()
        resp = self.client.get(reverse("mobile_api:course_access", args=[self.paid.pk]))
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(resp.data["has_access"])
        Enrollment.objects.create(utilisateur=self.user, cours=self.paid, statut="active")
        resp = self.client.get(reverse("mobile_api:course_access", args=[self.paid.pk]))
        self.assertTrue(resp.data["has_access"])
        self.assertEqual(resp.data["source"], "enrollment")

    def test_curriculum_access_check_does_not_write_to_database(self):
        # GET pa dwe kreye Enrollment/SubscriptionAccess (kontrèman ak course_detail sou sit la)
        plan = SubscriptionPlan.objects.create(nom="Plan", prix=100, max_courses=0)
        plan.cours.add(self.paid)
        Subscription.objects.create(
            utilisateur=self.user, plan=plan, statut="active",
            date_fin=timezone.now() + timedelta(days=5),
        )
        self.auth()
        resp = self.client.get(self.curriculum_url(self.paid))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(SubscriptionAccess.objects.count(), 0)
        self.assertEqual(Enrollment.objects.count(), 0)


class SubscriptionAccessTests(MobileApiBase):
    def _sub(self, plan, statut="active", days=10):
        return Subscription.objects.create(
            utilisateur=self.user, plan=plan, statut=statut,
            date_fin=timezone.now() + timedelta(days=days),
        )

    def test_unlimited_plan_active(self):
        plan = SubscriptionPlan.objects.create(nom="Illimité", prix=100, max_courses=0)
        plan.cours.add(self.paid)
        self._sub(plan)
        self.auth()
        resp = self.client.get(reverse("mobile_api:course_access", args=[self.paid.pk]))
        self.assertTrue(resp.data["has_access"])
        self.assertEqual(resp.data["source"], "subscription")
        self.assertIsNotNone(resp.data["expires_at"])

    def test_unlimited_plan_does_not_cover_other_courses(self):
        other_paid = Course.objects.create(titre="Autre payant", publie=True, prix=900)
        plan = SubscriptionPlan.objects.create(nom="Illimité", prix=100, max_courses=0)
        plan.cours.add(self.paid)
        self._sub(plan)
        self.auth()
        self.assertEqual(self.client.get(self.curriculum_url(other_paid)).status_code, 403)

    def test_expired_subscription_has_no_access(self):
        plan = SubscriptionPlan.objects.create(nom="Illimité", prix=100, max_courses=0)
        plan.cours.add(self.paid)
        self._sub(plan, days=-1)
        self.auth()
        self.assertEqual(self.client.get(self.curriculum_url(self.paid)).status_code, 403)

    def test_pending_subscription_has_no_access(self):
        plan = SubscriptionPlan.objects.create(nom="Illimité", prix=100, max_courses=0)
        plan.cours.add(self.paid)
        self._sub(plan, statut="pending")
        self.auth()
        self.assertEqual(self.client.get(self.curriculum_url(self.paid)).status_code, 403)

    def test_limited_plan_only_selected_courses(self):
        chosen = self.paid
        not_chosen = Course.objects.create(titre="Non choisi", publie=True, prix=700)
        plan = SubscriptionPlan.objects.create(nom="Limité", prix=100, max_courses=1)
        plan.cours.add(chosen, not_chosen)
        sub = self._sub(plan)
        SubscriptionCourseSelection.objects.create(subscription=sub, course=chosen)
        self.auth()
        self.assertEqual(self.client.get(self.curriculum_url(chosen)).status_code, 200)
        self.assertEqual(self.client.get(self.curriculum_url(not_chosen)).status_code, 403)

    def test_other_users_subscription_does_not_grant_access(self):
        plan = SubscriptionPlan.objects.create(nom="Illimité", prix=100, max_courses=0)
        plan.cours.add(self.paid)
        Subscription.objects.create(
            utilisateur=self.other, plan=plan, statut="active",
            date_fin=timezone.now() + timedelta(days=10),
        )
        self.auth(self.user)
        self.assertEqual(self.client.get(self.curriculum_url(self.paid)).status_code, 403)


@override_settings(STORAGES=LOCAL_STORAGES)
class WebsiteStillWorksTests(TestCase):
    """Sit entènèt la dwe kontinye mache menm apre ajoute mobile_api."""

    def test_public_pages_still_render(self):
        for name in ("home", "courses:course_list"):
            response = self.client.get(reverse(name))
            self.assertEqual(response.status_code, 200, name)

    def test_health_check(self):
        self.assertEqual(self.client.get("/health/").status_code, 200)

    def test_web_login_page(self):
        self.assertEqual(self.client.get(reverse("accounts:login")).status_code, 200)
