"""
Chat mobil (modèl `chat.ChatRoom` / `chat.Message` ki egziste deja, pa gen migrasyon) :

  GET  /api/v1/chat/rooms/                          -> salon itilizatè a (patisipan)
  GET  /api/v1/chat/rooms/<id>/messages/?after=<id> -> mesaj (pajine pa `after`, max 100)
  POST /api/v1/chat/rooms/<id>/messages/            -> voye mesaj (idanpotan, `client_id`)
  POST /api/v1/chat/rooms/group/<course_id>/        -> louvri/kreye salon gwoup kou a

Règ (menm ak sit la, chat/views.py) :
  - sèlman patisipan yo wè/voye ; itilizatè a se request.user (JWT)
  - salon gwoup : sèlman moun ki gen aksè nan kou a (get_course_access) oswa staff
Dedoublonaj : modèl `Message` pa gen `client_id` (pa gen migrasyon) ; nou itilize
(1) cache Django `chatmsg:<user>:<client_id>` ; (2) garde-fou DB : menm mesaj, menm itilizatè,
menm salon nan 20 segonn ki sot pase. Sa pa 100 % si plizyè travayè gunicorn san cache pataje,
men evite doub anpil lè retry rezo.
"""

from datetime import timedelta

from django.core.cache import cache
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import CustomUser
from chat.models import ChatRoom, Message
from courses.models import Course

from .access import get_course_access

MAX_LEN = 2000
PAGE = 100


def _name(u):
    return u.get_full_name() or getattr(u, "username", "") or u.email


def _room_title(room, me):
    if room.type in ("private", "feedback"):
        other = next((p for p in room.participants.all() if p.pk != me.pk), None)
        if other is not None:
            return _name(other)
    return room.nom or f"Salon {room.pk}"


def _msg(m, me):
    return {
        "id": m.pk,
        "user_id": m.user_id,
        "user_name": _name(m.user),
        "mine": m.user_id == me.pk,
        "contenu": m.contenu,
        "reponse_a": m.reponse_a_id,
        "created_at": m.created_at,
    }


def _room_or_403(request, pk):
    room = get_object_or_404(ChatRoom, pk=pk)
    if not room.participants.filter(pk=request.user.pk).exists():
        return None
    return room


class RoomListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        rooms = (
            request.user.chat_rooms.all()
            .prefetch_related("participants")
            .order_by("-created_at")
        )
        data = []
        for r in rooms:
            last = r.messages.filter(is_deleted=False).select_related("user").last()
            data.append(
                {
                    "id": r.pk,
                    "titre": _room_title(r, request.user),
                    "type": r.type,
                    "course_id": r.course_id,
                    "participants_count": r.participants.count(),
                    "last_message": (
                        {
                            "contenu": last.contenu[:140],
                            "user_name": _name(last.user),
                            "created_at": last.created_at,
                        }
                        if last
                        else None
                    ),
                }
            )
        data.sort(
            key=lambda d: d["last_message"]["created_at"].timestamp() if d["last_message"] else 0,
            reverse=True,
        )
        return Response({"rooms": data})


class RoomMessagesView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        room = _room_or_403(request, pk)
        if room is None:
            return Response({"detail": "Vous n'avez pas accès à ce salon."}, status=403)
        qs = room.messages.filter(is_deleted=False).select_related("user")
        after = request.query_params.get("after")
        if after and after.isdigit():
            qs = qs.filter(pk__gt=int(after)).order_by("created_at")[:PAGE]
            items = list(qs)
        else:
            items = list(qs.order_by("-created_at")[:PAGE])[::-1]  # 100 dènye, ordre kwasan
        return Response({"room_id": room.pk, "messages": [_msg(m, request.user) for m in items]})

    def post(self, request, pk):
        room = _room_or_403(request, pk)
        if room is None:
            return Response({"detail": "Vous n'avez pas accès à ce salon."}, status=403)
        contenu = request.data.get("contenu")
        if not isinstance(contenu, str) or not contenu.strip():
            return Response({"detail": "Message vide."}, status=status.HTTP_400_BAD_REQUEST)
        contenu = contenu.strip()
        if len(contenu) > MAX_LEN:
            return Response(
                {"detail": f"Message trop long (max {MAX_LEN} caractères)."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        client_id = request.data.get("client_id")
        key = None
        if isinstance(client_id, str) and 0 < len(client_id) <= 64:
            key = f"chatmsg:{request.user.pk}:{client_id}"
            prev = cache.get(key)
            if prev:
                m = Message.objects.filter(pk=prev, room=room, user=request.user).first()
                if m:
                    return Response({**_msg(m, request.user), "duplicate": True})

        recent = Message.objects.filter(
            room=room,
            user=request.user,
            contenu=contenu,
            created_at__gte=timezone.now() - timedelta(seconds=20),
        ).first()
        if recent:
            if key:
                cache.set(key, recent.pk, 3600)
            return Response({**_msg(recent, request.user), "duplicate": True})

        reponse_a = None
        rid = request.data.get("reponse_a")
        if isinstance(rid, int):
            reponse_a = Message.objects.filter(pk=rid, room=room).first()
        m = Message.objects.create(room=room, user=request.user, contenu=contenu, reponse_a=reponse_a)
        if key:
            cache.set(key, m.pk, 3600)
        return Response({**_msg(m, request.user), "duplicate": False}, status=status.HTTP_201_CREATED)


class GroupRoomView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, course_id):
        course = get_object_or_404(Course, pk=course_id)
        # Menm règ aksè ak rès API a (enskripsyon aktif, abònman, kou gratis)
        has_access = get_course_access(request.user, course)["has_access"]
        if not (request.user.is_staff or has_access):
            return Response(
                {"detail": "Vous n'êtes pas inscrit à ce cours.", "code": "course_access_required"},
                status=403,
            )
        room = ChatRoom.objects.filter(type="group", course=course).first()
        created = False
        if room is None:
            room = ChatRoom.objects.create(
                type="group",
                nom=f"Groupe - {course.titre}",
                course=course,
                created_by=request.user,
            )
            room.participants.add(
                *CustomUser.objects.filter(inscriptions__cours=course, inscriptions__statut="active")
            )
            if request.user.is_staff:
                room.participants.add(*CustomUser.objects.filter(is_staff=True))
            created = True
        # Moun ki enskri apre kreyasyon salon an ajoute otomatikman
        room.participants.add(request.user)
        return Response(
            {"id": room.pk, "titre": room.nom, "type": room.type, "course_id": course.pk},
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )
