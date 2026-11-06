#!/usr/bin/env bash
# Prépare le projet Android (utilisé par GitHub Actions). Toute la logique est ici
# pour ne plus avoir à modifier le fichier workflow.
set -euo pipefail

if [ ! -f android/app/build.gradle ] && [ ! -f android/app/build.gradle.kts ]; then
  flutter create --platforms=android --project-name educadim --org com.dimensionproduction .
fi

# `flutter create` génère test/widget_test.dart (référence MyApp, absent ici) : on le retire.
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then
  rm -f test/widget_test.dart
fi

M=android/app/src/main/AndroidManifest.xml
if ! grep -q 'android.permission.INTERNET' "$M"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$M"
fi
sed -i 's#android:label="[^"]*"#android:label="EducaDim"#' "$M"
grep -q 'android.permission.INTERNET' "$M" || { echo "ERREUR: permission INTERNET absente"; exit 1; }

flutter pub get
dart run flutter_launcher_icons
echo "Projet Android prêt (INTERNET + icône)."
