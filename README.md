# EducaDim — client Flutter (fondation)

Client mobile du backend Django existant (`https://educadim.onrender.com/api/v1/`).
Prototype de référence : `reference/index.html` (palette, typographies, structure).

> **État honnête** : fondation fonctionnelle, **non compilée ni testée** dans
> l'environnement de création (pas de Flutter SDK ni d'accès réseau). Le contrat
> JSON du backend n'a pas pu être lu ; voir `docs/API_CONTRACT.md`.

## Opérationnel (côté app)
- Connexion JWT (`POST auth/login/`), jetons dans le stockage sécurisé, refresh
  automatique unique sur 401, déconnexion, redirection si session expirée.
- Routes privées protégées (go_router), navigation 5 onglets, bouton chat flottant.
- Thème fidèle au prototype, clair/sombre/auto, interface en français.
- SQLite : file d'attente `outbox` (id client stable, anti-doublon, jamais
  supprimée avant confirmation), chat local, téléchargements.
- Synchronisation : détection du retour réseau (connectivity_plus), flush
  automatique et manuel, indicateurs (Hors ligne / n en attente / À jour).
- Chat : historique local, envoi hors ligne mis en attente.
- Téléchargements : service de téléchargement/suppression + écran (stockage utilisé).
- Tests unitaires : `test/outbox_sync_test.dart`.

## Nécessite le backend / un contrat confirmé
Catalogue, détail de cours, inscriptions, leçons/quiz/flashcards, progression
distante, profil, chat serveur, notifications/push. Les écrans correspondants
affichent un état explicite « connexion à finaliser » (aucune donnée fictive).
Inscription : ouvre la page web officielle (aucun endpoint d'inscription confirmé).

## Lancer
```
flutter create --platforms=android --project-name educadim --org com.dimensionproduction .
# ajouter <uses-permission android:name="android.permission.INTERNET"/> dans
# android/app/src/main/AndroidManifest.xml (le workflow CI le fait automatiquement)
flutter pub get
flutter analyze && flutter test
flutter run --dart-define=API_BASE_URL=https://educadim.onrender.com/api/v1/
flutter build apk --release
```
APK automatique : workflow `.github/workflows/android.yml` (artefact `educadim-apk`).
Polices : DM Sans / Manrope via `google_fonts` (téléchargées au premier usage ;
embarquez-les dans `assets/` pour un usage 100 % hors ligne).
