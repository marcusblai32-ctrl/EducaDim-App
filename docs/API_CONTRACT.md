# Contrat API EducaDim — état final

Source : `mobile_api/` du dépôt Django + les ajouts de `backend_patch/` (`mobile_api_complet.zip`).
Préfixe `/api/v1/`, en-tête `Accept-Language: fr`. Détails des endpoints : `backend_patch/mobile_api/README.md`.

## Natif (déjà dans le backend d'origine)
`auth/login/`, `auth/token/refresh/`, `me/`, `courses/`, `courses/<id>/`, `courses/<id>/curriculum/`, `lessons/<id>/`.

## Ajoutés par le patch (aucun modèle, aucune migration)
Progression (`lessons/<id>/complete/`, `me/progress/`, `me/activity/`), flashcards, notifications,
quiz (start/submit/résultat, correction serveur), chat (salons, messages, salon de groupe),
certificats (lecture seule), administration de contenu (`admin/...`).

## Choix de conception
- **Pas de paiement en ligne dans l'app** : un cours payant ouvre la page du cours sur le site.
- **Certificats** : affichage (statut, numéro) ; le téléchargement PDF se fait sur le site.
- **Administration** : visible dans Profil seulement si `admin/capabilities/` renvoie `can_manage`;
  le serveur contrôle chaque action (superuser, ou staff avec `add_<modèle>`).
- **Téléphones partagés** : chaque opération en file porte `_owner` (identité du compte) et n'est envoyée
  qu'avec le jeton de son propriétaire ; changer de compte purge caches et progression locale (pas la file).
- **Idempotence** : progression (`lesson-<id>`), quiz (`attempt_id`), lecture notif (`notif-read-<id>`),
  chat (`client_id` ; dédoublonnage cache + fenêtre de 20 s côté serveur, sans migration).

## Limites restantes
- Push FCM : nécessite Firebase (clé serveur + `google-services.json`) et un modèle de jeton d'appareil ;
  l'app interroge le serveur (au lancement, après sync, toutes les 90 s ouverte ; chat toutes les 8 s ouvert).
- Quiz à réponses audio/vidéo/image/fichier : à passer sur le site. Upload de fichiers dans le contenu
  (admin) : sur le site ; l'app accepte texte et URL.
- Médias de leçon : téléchargeables un par un (URL directes), sans manifeste signé.
