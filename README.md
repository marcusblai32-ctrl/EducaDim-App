# EducaDim — client Flutter

Client mobile du backend Django existant (`https://educadim.onrender.com/api/v1/`),
construit sur l'API `mobile_api/` du dépôt. Prototype de référence : `reference/index.html`.

> **État honnête** : le code a été écrit **sans pouvoir exécuter Flutter** (pas de SDK ni
> de réseau dans l'environnement). `flutter analyze`, `flutter test` et la compilation
> n'ont **pas** été lancés ; des corrections mineures peuvent être nécessaires au premier
> build. Flutter ≥ 3.27 requis (`withValues`, `CardThemeData`).

## Fonctionnalités opérationnelles (contre l'API réelle)
- Connexion (e-mail ou user_id), jetons JWT en stockage sécurisé, refresh avec rotation
  (un seul refresh concurrent), session expirée → retour à la connexion, déconnexion.
- Accueil personnalisé (prénom, reprise de la dernière leçon, recommandations, statistiques locales).
- Explorer : catalogue paginé côté serveur, recherche, filtre gratuit/payant, détail, prérequis, état d'accès.
- Mes cours : cours accessibles (inscription active, abonnement, gratuit).
- Programme (unités/modules/leçons) et lecteur de leçon : textes, images, liens, PDF/audio/vidéo
  (ouverture externe + téléchargement fichier).
- Gestion des 403 métier (`course_access_required`, `lesson_quiz_required`).
- Hors ligne : cache SQLite des réponses, « Télécharger le cours » (structure + contenu des
  leçons), bandeau « hors ligne », progression de leçon enregistrée localement.
- File d'attente (`outbox`) idempotente + service de synchronisation automatique au retour du réseau.
- Chat local avec envoi différé ; profil ; thème clair/sombre ; téléchargements (liste, taille, suppression).

## Patch backend fourni (à déployer)
`backend_patch/` (dans l'archive de livraison) ajoute progression, `me/progress/`, `me/activity/`, notifications, flashcards et quiz.
Après déploiement : les leçons terminées se synchronisent automatiquement (aller + retour).

## Dépend d'endpoints absents du backend
Progression distante, quiz, flashcards, chat serveur, notifications/push, certificats,
inscription in-app, manifest/URL signées pour médias. Détail : `docs/API_CONTRACT.md`.
Tant que `UnconfiguredGateway` est en place, ces données restent en file locale, jamais supprimées.

## Lancer / compiler
```
flutter create --platforms=android --project-name educadim --org com.dimensionproduction .
# ajouter <uses-permission android:name="android.permission.INTERNET"/> au manifeste Android
flutter pub get && flutter analyze && flutter test
flutter run --dart-define=API_BASE_URL=https://educadim.onrender.com/api/v1/
flutter build apk --release
```
APK automatique : `.github/workflows/android.yml` (artefact `educadim-apk`).
Le serveur Render gratuit peut mettre ~30 s à se réveiller : les délais sont de 20 s/30 s, relancez si besoin.
