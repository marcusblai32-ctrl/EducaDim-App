# Contrat API EducaDim — état réel

Source : `mobile_api/` du dépôt Django (urls.py, views.py, serializers.py, README.md),
lu directement dans le ZIP fourni. Préfixe `/api/v1/`, header `Accept-Language: fr`.

## Utilisé par l'app (confirmé dans le code)
| Endpoint | Usage |
|---|---|
| `POST auth/login/` `{username,password}` (username = e-mail ou user_id) | connexion → `access`, `refresh`, `user` |
| `POST auth/token/refresh/` `{refresh}` | rafraîchissement (rotation : le nouveau refresh est conservé) |
| `GET me/` | profil |
| `GET courses/?search=&prix=gratuit\|payant&page=` | catalogue paginé (+ bloc `access`) |
| `GET courses/<id>/` | détail, prérequis, compteurs |
| `GET courses/<id>/curriculum/` | unités → modules → leçons (403 `course_access_required`) |
| `GET lessons/<id>/` | sections et contenus (403 `lesson_quiz_required`) |

« Mes cours » = cours dont `access.has_access` est vrai (toutes les pages du catalogue).
Les réponses réussies sont mises en cache SQLite ; hors ligne, le dernier contenu connu est relu.

## Ajouts proposés (backend_patch/ : progress_views.py + urls.py, aucun modèle ni migration)
| Endpoint | Usage |
|---|---|
| `POST lessons/<id>/complete/` | marque la leçon terminée, idempotent (201 nouvelle, 200 déjà faite, 403 `lesson_quiz_required` / `course_access_required`) |
| `GET me/progress/` | leçons terminées + pourcentage par cours (récupération au retour du réseau) |
| `GET me/activity/` | 30 dernières activités |
| `GET notifications/` (`?unread=1`, paginé) | liste des notifications |
| `GET notifications/unread-count/` | compteur |
| `POST notifications/<id>/read/` | marquer lue (idempotent) |
| `POST notifications/read-all/` | tout marquer lu |
| `GET courses/<id>/quizzes/` | quiz publiés + meilleur score |
| `GET quizzes/<id>/` | questions (sans bonnes réponses) |
| `POST quizzes/<id>/start/` | démarre/reprend une tentative (idempotent) |
| `POST quiz-attempts/<id>/submit/` | soumission + correction serveur (idempotent) |
| `GET quiz-attempts/<id>/` | résultat |
| `GET courses/<id>/flashcards/` | flashcards (403 `course_access_required`) |

Tant que ce patch n'est pas déployé : la progression reste en file locale (rien n'est perdu)
et l'écran flashcards affiche « pas encore disponible sur le serveur ».

## NON disponible côté backend (rien n'est simulé dans l'app)
1. **Écriture de progression** : voir le patch ci-dessus. Sans lui, l'app enregistre localement
   (`local_progress`) et met `lesson_completed` en file (id `lesson-<id>`, payload
   `lesson_id`, `course_id`, `completed_at`). À câbler dans `SyncGateway.push`
   (README backend : POST appelant `ProgresLecon.terminer()`, ignorer les renvois
   si la leçon est déjà terminée).
2. **Quiz** : endpoints dans le patch (types single, vrai_faux, multiple, texte_trous, texte_libre ; les quiz
   audio/vidéo/fichier restent à passer sur le site) et **flashcards**
   (`courses.Flashcard`, seul `flashcards_count` est exposé) : écrans non construits.
3. **Chat** : modèles `ChatRoom`/`Message` existent, pas d'endpoint JSON.
   L'app garde l'historique local et met `chat_message` en file (`client_id`, `body`, `created_at`).
4. **Notifications** : endpoints dans le patch (lecture/marquage). **Push FCM** : toujours absent
   (nécessite un modèle de jeton d'appareil + Firebase) ; l'app interroge le serveur (90 s).
5. **Certificats** : pas d'endpoint.
6. **Inscription à un cours / création de compte** : pas d'endpoint ; l'app ouvre le site.
7. **Téléchargement des médias** : `courses/<id>/manifest/` et URL signées sont
   « poko enplemante » (README backend). L'app met en cache structure + textes + URLs
   des leçons ; les fichiers sont téléchargeables un par un via les URL directes
   (PDF, audio, fichier) sans chiffrement ni contrôle de licence.

## Points d'intégration dans le code
- `core/sync/sync_gateway.dart` → implémenter `push` (progression, chat).
- `main.dart` → injecter la passerelle réelle à la place de `UnconfiguredGateway`.
