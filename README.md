# EducaDim — client Flutter

Client mobile du backend Django existant (`https://educadim.onrender.com/api/v1/`),
construit sur l'API `mobile_api/` du dépôt. Prototype de référence : `reference/index.html`.

> **État honnête** : le code a été écrit **sans pouvoir exécuter Flutter** (pas de SDK ni
> de réseau dans l'environnement). `flutter analyze`, `flutter test` et la compilation
> n'ont **pas** été lancés ; des corrections mineures peuvent être nécessaires au premier
> build. Flutter ≥ 3.27 requis (`withValues`, `CardThemeData`).

## Fonctionnalités
- Connexion JWT sécurisée, refresh automatique, session expirée, déconnexion, protection des routes.
- Accueil, catalogue (recherche, filtre), détail de cours, prérequis, programme, leçons (texte, image, liens,
  PDF/audio/vidéo), progression locale + serveur (aller-retour), « Ma progression » et activités récentes.
- Quiz (chaînes de questions, minuteur, correction serveur, résultat détaillé, envoi différé hors ligne),
  flashcards, certificats (affichage ; téléchargement sur le site).
- Chat par salons (discussion de cours), messages différés hors ligne ; notifications (badge, lu/non lu).
- Hors ligne : cache SQLite, cours téléchargeables, file d'attente idempotente, synchronisation automatique.
- Images de cours : cache disque, remplissage 16:9 du card, visuel de marque si indisponible.
- Administration (admin/staff autorisés, via Profil) : créer cours (brouillon), unités, modules, leçons, sections,
  contenus (texte/URL) et quiz + questions ; publier/dépublier.
- Téléphones partagés : isolation des données entre comptes.
- Thème clair/sombre, interface en français. Pas de paiement en ligne (cours payant → site).

## Backend
Appliquer `backend_patch/` (ou `mobile_api_complet.zip`) sur le dépôt Django : aucune migration.
Voir `docs/API_CONTRACT.md` pour le détail et les limites (push FCM, quiz à fichiers/audio).

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
