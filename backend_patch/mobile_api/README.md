# mobile_api — API REST pou aplikasyon Flutter EducaDim

Aplikasyon sa a **pa gen okenn modèl** (pa gen migrasyon). Li li menm baz done ak sit la
(`CustomUser`, `Course`, `Unite/Module/Lecon`, `Enrollment`, `Subscription*`).
Prefix: `/api/v1/` (san prefix lang). Lang: header `Accept-Language: fr|ht`.

## Otantifikasyon
Header: `Authorization: Bearer <access>`. Access = 15 min, refresh = 14 jou
(`SIMPLE_JWT` ki deja nan settings; `ROTATE_REFRESH_TOKENS=True`: chak refresh bay yon refresh nouvo,
Flutter dwe sere li).

### POST /api/v1/auth/login/
```json
{ "username": "student@example.com", "password": "..." }
```
`username` = email **oubyen** user_id (menm jan ak sit la). 200:
```json
{
  "access": "eyJ...", "refresh": "eyJ...",
  "user": { "id": 7, "user_id": "PM00-A1B2C3", "email": "student@example.com",
            "first_name": "Marie", "last_name": "Pierre", "full_name": "Marie Pierre",
            "birth_year": 2000, "phone_number": null,
            "receive_email_notifications": true, "receive_sms_notifications": false,
            "is_staff": false, "date_joined": "2026-01-10T14:00:00Z",
            "active_subscriptions": [] }
}
```
Erè: `401 {"detail": "...", "code": "invalid_credentials"}`, `403 {"code": "account_locked"}` (django-axes),
`429` (throttle 10/min), `400` (chan manke).

### POST /api/v1/auth/token/refresh/
`{"refresh": "eyJ..."}` → `{"access": "...", "refresh": "..."}` (401 si refresh envalid/ekspire).

### GET /api/v1/me/
Retounen menm objè `user` ki anwo a. 401 si pa gen token.

## Kou (tout bezwen token)
### GET /api/v1/courses/
Filt: `?search= &category=<id> &niveau=<id> &prix=gratuit|payant &learning_path=<id> &page=`.
```json
{ "count": 2, "next": null, "previous": null, "results": [
  { "id": 3, "titre": "Kou ki peye", "titre_fr": "Cours payant", "titre_ht": "Kou ki peye",
    "description": "...", "image": "https://.../a.jpg", "prix": "1500.00", "est_payant": true,
    "duree": 12,
    "categorie": {"id": 1, "nom": "Langues"},
    "niveau": {"id": 1, "code": "debutant", "label": "Débutant"},
    "learning_path": null, "position": 0, "inscription_possible": true,
    "updated_at": "2026-10-01T10:00:00Z",
    "access": {"has_access": false, "source": null, "enrollment_status": null, "expires_at": null} } ] }
```
`access.source` ∈ `enrollment | subscription | free | null`. `enrollment_status` ∈ `pending|active|rejected|cancelled|null`.

### GET /api/v1/courses/<id>/
Menm chan ak lis la, plis: `description_fr`, `description_ht`, `created_at`, `unites_count`,
`flashcards_count`, `quizzes_count`, `previous_course_id`, `next_course_id`,
`prerequisites: [{"course_id", "titre", "obligatoire", "completed"}]`, `prerequisites_completed`.
404 si kou a pa piblye (sit la pa tcheke sa; API a tcheke — staff ka wè brouyon).

### GET /api/v1/courses/<id>/access/
Toujou 200: `{"course_id": 3, "has_access": true, "source": "subscription", "enrollment_status": null, "expires_at": "2026-11-14T00:00:00Z"}`

### GET /api/v1/courses/<id>/curriculum/  (KONTNI PWOTEJE)
200 (gen aksè):
```json
{ "course_id": 3, "course_updated_at": "2026-10-01T10:00:00Z",
  "unites": [ { "id": 1, "titre": "Unité 1", "description": "", "ordre": 1,
    "modules": [ { "id": 1, "titre": "Module 1", "description": "", "ordre": 1,
      "lecons": [ { "id": 1, "titre": "Leson 1", "titre_fr": "Leçon 1", "titre_ht": "Leson 1",
                    "description": "", "ordre": 1 } ] } ] } ] }
```
403 (pa gen aksè):
```json
{ "detail": "Vous devez être inscrit ou avoir un abonnement actif pour accéder à ce contenu.",
  "code": "course_access_required", "course_id": 3, "enrollment_status": "pending" }
```
Se sèlman estrikti (leson aktif sèlman), pa kontni leson yo.

## Règ aksè (menm ak sit la, li sèlman — GET pa janm ekri nan baz done)
1. Kou gratis (`prix = 0`) → nenpòt itilizatè konekte.
2. `Enrollment.statut == 'active'`.
3. Abònman `active` ki pa ekspire: `SubscriptionAccess`, oswa plan `max_courses=0` ki gen kou a,
   oswa `SubscriptionCourseSelection` pou plan ak limit.
`pending/rejected/cancelled` pa bay aksè. Itilizatè a pa janm voye ID li: se JWT ki idantifye li.

## Kijan pou entegre fonksyon lavni yo (SAN modèl doublon)
| Fonksyon | Sa ki egziste deja | Sa ki ta manke |
|---|---|---|
| Leson/seksyon/kontni (videyo, odyo, PDF, tèks, imaj) | `Lecon`, `SectionLecon`, `Contenu` (type_contenu + url_* / fichier_*; FR + HT) | sèlman endpoint + serializer (`/lessons/<id>/`), ak règ "quiz leson dwe reyisi anvan" ki sou sit la (`lesson_detail`) |
| Quiz | `Quiz`, `Question`, `Reponse`, `TentativeQuiz`, `ReponseUtilisateur` + `quiz/services.py` | sèlman endpoint ki rele menm sèvis yo (pa re-kalkile nòt nan API a) |
| Flashcards | `courses.Flashcard` (`flashcards_count` deja nan detay kou) | endpoint lis |
| Pwogrè | `ProgresLecon`, `ProgresCours` (`terminer()` rekalkile kou a) | endpoint POST ki rele `terminer()` |
| Sètifika | `certificates.Certificate` (+ PDF `pdf_content`) | endpoint lis + telechajman PDF (menm règ ak `download_certificate`) |
| Chat (polling) | `ChatRoom`, `Message`; polling `salon/<id>/messages/<last_id>/` | endpoint JSON ki sèvi menm requête yo; PA Channels/Redis |
| Notifikasyon | `notifications.Notification` | endpoint lis/mark-read |
| FCM push | — | **Se sèl bagay ki mande yon modèl nouvo** (token aparèy pa itilizatè); pa gen doublon posib. Voye push an plis nan `utils/notifications.py` |
| Download manager / offline sync | — | Gade pi ba |
| Course versioning | `Course.updated_at` sèlman | Gade pi ba |

## Kontni offline — konsepsyon (poko enplemante)
**Manifest**: `GET /courses/<id>/manifest/` (aksè verifye menm jan ak `curriculum`) → lis fichye
(`lecon_id`, `contenu_id`, `type`, `size`, `sha256` **kòm tchèk entegrite sèlman, pa chifreman**,
`version`) + `course_version` + `expires_at` (fen abònman, oubyen `null` pou enrollment).
**Otorizasyon download**: pa fichye, yon URL siyen kout (R2 presigned, 5–15 min) bay apre yon nouvo
verifikasyon aksè. **Chifreman**: Flutter chifre chak fichye *at rest* ak AES-256-GCM, kle a
estoke nan Keystore (Android) / Keychain (iOS); si sèvè a bay yon kle kontni, se kle sa a ki
*wrapped* ak kle aparèy la, bay sèlman pou itilizatè otorize, ak dat ekspirasyon (lisans offline =
`expires_at`). Lè abònman ekspire, aplikasyon an efase kle a. **Sa pa ofri pwoteksyon absoli kont
kopi**: yon itilizatè ki gen aksè ka toujou anrejistre/ekstrè kontni an sou aparèy li; objektif la
se anpeche aksè san otorizasyon ak kopi fasil, pa DRM konplè.
**Offline sync**: Flutter kenbe yon fil POST lokal (`leson terminée`) epi voye l lè rezo a retounen
(`ProgresLecon` gen `unique_together` sou `utilisateur+lecon`, kidonk pa gen doublon; men `terminer()` reekri `date_fin` a chak apèl, kidonk sèvè a dwe inyore re-voye yo si leson an deja `termine`).


---

## Adisyon (pa gen migrasyon, pa gen modèl nouvo)

Fichye nouvo : `progress_views.py`, `notification_views.py`, `quiz_views.py`, `chat_views.py`,
`certificate_views.py`, `admin_views.py` ; `urls.py` ajou. Tout wout pwoteje pa JWT.

### Pwogrè, aktivite, flashcards, notifikasyon
| Metòd | Wout | Deskripsyon |
|---|---|---|
| POST | `/lessons/<id>/complete/` | Leson fini (idanpotan : 201 nouvo, 200 deja fini). 403 `lesson_quiz_required` / `course_access_required` |
| GET | `/me/progress/` | `{lessons:[…], courses:[{course_id,pourcentage}]}` |
| GET | `/me/activity/` | 30 dènye aktivite |
| GET | `/courses/<id>/flashcards/` | Flashcards (aksè pwoteje) |
| GET | `/notifications/` (`?unread=1`) | Pajine |
| GET | `/notifications/unread-count/` | `{unread}` |
| POST | `/notifications/<id>/read/` , `/notifications/read-all/` | Make li (idanpotan) |

### Quiz
| Metòd | Wout | Deskripsyon |
|---|---|---|
| GET | `/courses/<id>/quizzes/` | Quiz pibliye + `best_score`, `passed`, `mobile_compatible` |
| GET | `/quizzes/<id>/` | Kesyon (SAN `est_correcte`) |
| POST | `/quizzes/<id>/start/` | Kòmanse/rekòmanse tantativ (idanpotan) |
| POST | `/quiz-attempts/<id>/submit/` | `{answers:[{question_id, reponse_ids, texte}]}` → korije sèvè-side (idanpotan) |
| GET | `/quiz-attempts/<id>/` | Rezilta (detay sèlman apre soumisyon) |

Tip sipòte : single, vrai_faux, multiple, texte_trous, texte_libre.

### Chat
| Metòd | Wout | Deskripsyon |
|---|---|---|
| GET | `/chat/rooms/` | Salon itilizatè a (patisipan) |
| GET | `/chat/rooms/<id>/messages/?after=<id>` | Mesaj (max 100) |
| POST | `/chat/rooms/<id>/messages/` | `{contenu, client_id}` — dedoublonaj (cache + fenèt 20 s) |
| POST | `/chat/rooms/group/<course_id>/` | Louvri/kreye salon gwoup (aksè kou a obligatwa) |

### Sètifika (LEKTI SÈLMAN — telechajman PDF sou sit la)
| GET | `/certificates/` | Lis, estati, nimewo, lyen verifikasyon + paj telechajman sit la |

### Administrasyon kontni (admin / staff ak pèmisyon Django `add_<modèl>`)
| Metòd | Wout | Deskripsyon |
|---|---|---|
| GET | `/admin/capabilities/` | `{can_manage, can:{course,unite,module,lecon,section,contenu,quiz,question}}` |
| GET | `/admin/meta/` | Kategori, nivo, tip seksyon/kontni |
| GET/POST | `/admin/courses/` | Kou jerab / kreye (toujou BWOUYON `publie=false`) |
| PATCH | `/admin/courses/<id>/` | `{publie}` (superuser oswa `courses.change_course`) |
| GET | `/admin/courses/<id>/tree/` | Estrikti + quiz |
| POST | `/admin/courses/<id>/unites/` · `/admin/unites/<id>/modules/` · `/admin/modules/<id>/lecons/` · `/admin/lecons/<id>/sections/` · `/admin/sections/<id>/contenus/` | Kreye |
| POST | `/admin/quizzes/` | `{niveau: cours\|module\|lecon, parent_id, titre, …}` (brouyon) |
| PATCH | `/admin/quizzes/<id>/` | `{publie}` (mande omwen 1 kesyon) |
| POST | `/admin/quizzes/<id>/questions/` | single, multiple, vrai_faux, texte_trous, texte_libre (validasyon repons) |

Sekirite : sèvè a verifye pèmisyon pou CHAK aksyon (bouton aplikasyon an se sèlman afichaj). Staff ki pa gen
`courses.change_course` pa ka ajoute anba kou lòt moun (sèlman kreyatè a).

Poko fèt : push FCM, manifest/telechajman medya siyen, kesyon quiz audio/vidéo/fichye, upload fichye nan kontni.
