"""
Sètifika mobil (LEKTI SÈLMAN : telechajman PDF fèt sou sit la) (modèl `certificates.Certificate`, pa gen migrasyon) :

  GET  /api/v1/certificates/                    -> sètifika itilizatè a

Menm règ ak certificates/views.py. Yon sètifika kreye lè kou a 100 % (menm backfill ak sit la).
"""

from django.shortcuts import get_object_or_404
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from certificates.models import Certificate
from progress.models import ProgresCours


def _backfill(user):
    for p in ProgresCours.objects.filter(utilisateur=user, pourcentage__gte=100).select_related("cours"):
        Certificate.objects.get_or_create(
            student=user,
            course=p.cours,
            defaults={
                "student_name": user.get_full_name() or user.email,
                "completed_at": p.date_modification,
            },
        )


def _ser(c, request):
    return {
        "public_id": str(c.public_id),
        "number": c.certificate_number,
        "course_id": c.course_id,
        "course_title": c.course.get_titre() if hasattr(c.course, "get_titre") else c.course.titre,
        "student_name": c.student_name,
        "status": c.status,
        "status_label": c.get_status_display(),
        "editable": c.status in (Certificate.Status.PENDING, Certificate.Status.CORRECTION),
        "review_note": c.review_note or None,
        "student_note": c.student_note or None,
        "completed_at": c.completed_at,
        "issued_at": c.issued_at,
        "verify_url": request.build_absolute_uri(f"/fr/certificats/verifier/{c.public_id}/"),
        "download_page_url": request.build_absolute_uri("/fr/certificats/"),
    }


class MyCertificatesView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        _backfill(request.user)
        qs = Certificate.objects.filter(student=request.user).select_related("course")
        return Response({"certificates": [_ser(c, request) for c in qs]})
