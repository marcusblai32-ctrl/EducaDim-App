"""
Notifikasyon mobil (modèl `notifications.Notification` ki egziste deja, pa gen migrasyon) :

  GET  /api/v1/notifications/              (?unread=1, pajine)
  GET  /api/v1/notifications/unread-count/
  POST /api/v1/notifications/<id>/read/    (idanpotan)
  POST /api/v1/notifications/read-all/

Chak itilizatè wè sèlman pwòp notifikasyon li (request.user, JWT).
Pa gen push FCM isit la : aplikasyon an poll endpoint sa yo.
"""

from django.shortcuts import get_object_or_404
from rest_framework.generics import GenericAPIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from notifications.models import Notification


def _serialize(n):
    return {
        "id": n.pk,
        "type": n.type_notif,
        "titre": n.titre,
        "message": n.message,
        "lien": n.lien or None,
        "lue": n.lue,
        "date": n.date,
    }


class NotificationListView(GenericAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = Notification.objects.filter(utilisateur=request.user).order_by("-date")
        if request.query_params.get("unread") in ("1", "true"):
            qs = qs.filter(lue=False)
        page = self.paginate_queryset(qs)
        items = page if page is not None else list(qs[:50])
        data = [_serialize(n) for n in items]
        if page is not None:
            return self.get_paginated_response(data)
        return Response(data)


class NotificationUnreadCountView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(
            {"unread": Notification.objects.filter(utilisateur=request.user, lue=False).count()}
        )


class NotificationReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        n = get_object_or_404(Notification, pk=pk, utilisateur=request.user)
        if not n.lue:
            n.lue = True
            n.save(update_fields=["lue"])
        return Response({"id": n.pk, "lue": True})


class NotificationReadAllView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        updated = Notification.objects.filter(utilisateur=request.user, lue=False).update(lue=True)
        return Response({"updated": updated})
