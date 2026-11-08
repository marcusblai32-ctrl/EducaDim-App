# EducaDim — application mobile (Flutter)

Application Android d'apprentissage : cours, leçons, quiz, flashcards par module, certificats,
discussions, notifications, mode hors ligne, interface en français et en kreyòl, thème clair/sombre.

## Compiler l'APK
**Avec GitHub Actions (recommandé)** : envoyez le ZIP du projet dans le dossier `upload/` du dépôt ;
le workflow décompresse, prépare Android (permission Internet, icône) et publie l'APK dans *Releases*.

**En local**
```
flutter create --platforms=android --project-name educadim --org com.dimensionproduction .
bash tool/ci_prepare.sh
flutter build apk --release
```
Prérequis : Flutter stable récent (3.27 ou plus).

## Organisation
`lib/core` (thème, langue, réseau, base locale, synchronisation) · `lib/features` (écrans par fonctionnalité) ·
`assets` (logo et icône) · `reference` (prototype d'origine).
