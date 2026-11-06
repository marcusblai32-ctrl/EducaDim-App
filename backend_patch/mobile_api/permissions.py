from rest_framework.exceptions import APIException
from rest_framework.permissions import BasePermission

from .access import get_course_access


class CourseAccessRequired(APIException):
    status_code = 403
    default_code = "course_access_required"

    def __init__(self, course_id, enrollment_status=None):
        detail = {
            "detail": (
                "Vous devez être inscrit ou avoir un abonnement actif "
                "pour accéder à ce contenu."
            ),
            "code": self.default_code,
            "course_id": course_id,
            "enrollment_status": enrollment_status,
        }

        # APIException konvèti valè primitif yo an ErrorDetail (string).
        # Nou konsève dict la apre super() pou course_id rete yon integer
        # nan repons JSON API a, jan kontra Flutter la mande l.
        super().__init__(detail=detail)
        self.detail = detail


class HasCourseAccess(BasePermission):
    """
    Permission objè: obj = Course.
    Menm règ ak sit la (gratis | Enrollment 'active' | abònman aktif).
    Itilizatè a pa janm voye pwòp ID li: se request.user (JWT) ki itilize.
    """

    def has_object_permission(self, request, view, obj):
        access = get_course_access(request.user, obj)
        if not access["has_access"]:
            raise CourseAccessRequired(
                obj.pk,
                access.get("enrollment_status"),
            )
        return True
