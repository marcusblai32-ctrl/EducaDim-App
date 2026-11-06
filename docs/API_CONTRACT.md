# Contrat API EducaDim — état réel

**Statut : non vérifié.** Lors de la construction, la lecture du code du dépôt
Django (sous-pages GitHub) était bloquée et `GET /api/v1/` renvoyait une erreur.
Aucun format JSON n'a donc été deviné au-delà des valeurs listées ci-dessous.

## Confirmé (cahier des charges)
- Base : `https://educadim.onrender.com/api/v1/`
- `POST auth/login/` (JWT)

## Hypothèses à valider (ApiContract dans `lib/core/config/api_config.dart`)
| Élément | Valeur actuelle | À vérifier |
|---|---|---|
| Champ identifiant | `email` | `email` ou `username` |
| Champ mot de passe | `password` | |
| Clés de jetons | `access` / `refresh` | noms exacts dans la réponse |
| Rafraîchissement | `POST auth/refresh/` `{refresh}` | chemin et corps |

## Endpoints à fournir / confirmer (rien n'est simulé côté app)
1. Profil : `GET me/` (nom, e-mail, avatar).
2. Catalogue : liste de cours (catégorie, niveau, prérequis, prix, image) + détail.
3. Inscriptions de l'utilisateur + `POST` d'inscription.
4. Structure d'un cours : modules → unités → leçons → sections, contenus
   (texte, vidéo/URL, fichiers téléchargeables), quiz/QCM, flashcards.
5. Progression : `POST` idempotent. Recommandé : corps avec `client_id` (UUID
   généré par l'app), `lesson_id`, `completed_at` (ISO 8601 UTC) ; réponse 200/201
   même si déjà reçu. Câblage : implémenter `SyncGateway.push` pour `kind=progress`.
6. Chat : `GET` historique + `POST` message avec `client_id` (idempotent).
   Câblage : `SyncGateway.push` pour `kind=chat_message` (payload :
   `client_id`, `body`, `created_at`).
7. Notifications : liste + marquer lu ; push (FCM) nécessitera un enregistrement
   de jeton d'appareil côté serveur et une clé Firebase (hors APK pour les secrets serveur).

## Points d'intégration dans le code
- `features/courses/course_repository.dart` → remplacer `UnconfiguredCourseRepository`.
- `core/sync/sync_gateway.dart` → remplacer `UnconfiguredGateway`.
- `main.dart` → injecter ces deux implémentations.
