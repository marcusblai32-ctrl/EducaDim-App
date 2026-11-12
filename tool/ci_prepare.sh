#!/usr/bin/env bash
# Prépare le projet Android (utilisé par GitHub Actions) : dossier android, permissions,
# notifications locales (rappels), icône. Toute la logique est ici.
set -euo pipefail

if [ ! -f android/app/build.gradle ] && [ ! -f android/app/build.gradle.kts ]; then
  flutter create --platforms=android --project-name educadim --org com.dimensionproduction .
fi

# ---- test par défaut généré par `flutter create` (référence MyApp absent) ----
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then rm -f test/widget_test.dart; fi

# ---- Manifeste : permissions + récepteurs des rappels programmés ----
M=android/app/src/main/AndroidManifest.xml
add_perm() {
  grep -q "android.permission.$1" "$M" || sed -i "s#<application#<uses-permission android:name=\"android.permission.$1\"/>\n    <application#" "$M"
}
add_perm INTERNET
add_perm POST_NOTIFICATIONS
add_perm VIBRATE
add_perm RECEIVE_BOOT_COMPLETED
add_perm SCHEDULE_EXACT_ALARM
add_perm USE_EXACT_ALARM
if ! grep -q "ScheduledNotificationReceiver" "$M"; then
  python3 - "$M" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read()
recv='''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    '''
s=s.replace('</application>',recv+'</application>',1)
open(p,'w').write(s)
PY
fi
sed -i 's#android:label="[^"]*"#android:label="EducaDim"#' "$M"
grep -q 'android.permission.INTERNET' "$M" || { echo "ERREUR: permission INTERNET absente"; exit 1; }

# ---- Gradle : desugaring requis par flutter_local_notifications ----
G=android/app/build.gradle.kts
[ -f "$G" ] || G=android/app/build.gradle
if ! grep -q "desugar_jdk_libs" "$G"; then
  python3 - "$G" <<'PY'
import sys,re
p=sys.argv[1]
s=open(p).read()
kts=p.endswith('.kts')
flag='isCoreLibraryDesugaringEnabled = true' if kts else 'coreLibraryDesugaringEnabled true'
dep=('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' if kts
     else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'")
s=re.sub(r'(compileOptions\s*\{)', r'\1\n        '+flag, s, count=1)
s=s.rstrip()+'\n\ndependencies {\n    '+dep+'\n}\n'
open(p,'w').write(s)
PY
fi

# ---- Icône de notification (silhouette blanche du logo) + R8 désactivé (workmanager/plugins) ----
if [ -d assets/android_res ]; then
  cp -r assets/android_res/. android/app/src/main/res/
fi
[ -f android/app/src/main/res/drawable-mdpi/ic_stat_educadim.png ] || { echo "ERREUR: icône de notification absente"; exit 1; }
[ -f android/app/src/main/res/raw/snd_reminder.wav ] || { echo "ERREUR: sons de notification absents (res/raw)"; exit 1; }
if ! grep -q "isMinifyEnabled" "$G" ; then
  python3 - "$G" <<'PY'
import sys,re
p=sys.argv[1]
s=open(p).read()
kts=p.endswith('.kts')
line=('isMinifyEnabled = false\n            isShrinkResources = false' if kts
      else 'minifyEnabled false\n            shrinkResources false')
if re.search(r'release\s*\{',s):
    s=re.sub(r'(release\s*\{)', r'\1\n            '+line, s, count=1)
open(p,'w').write(s)
PY
fi

# ---- Lint désactivé : le lint d'Android plante (bug d'outil) sur url_launcher/webview ----
mkdir -p "$HOME/.gradle/init.d"
cat > "$HOME/.gradle/init.d/nolint.gradle" <<'GRADLE'
allprojects {
    tasks.configureEach { t ->
        if (t.name.startsWith("lintVital") || t.name.startsWith("lintAnalyze") || t.name.startsWith("lintReport") || t.name == "lint") {
            t.enabled = false
        }
    }
}
GRADLE

# ---- Sons de l'interface (succès / échec / terminé) : paquet audio ajouté seulement ici (CI),
# pubspec.yaml du dépôt reste intact. Si l'ajout échoue, on garde la version de base (clic système).
if flutter pub add audioplayers; then
  cp tool/sfx_backend_audioplayers.dart.txt lib/core/audio/sfx_backend.dart
  echo "Sons activés (audioplayers)."
else
  echo "AVERTISSEMENT: audioplayers indisponible, sons d'interface en version de base."
fi

flutter pub get
dart run flutter_launcher_icons
echo "Projet Android prêt (Internet, notifications, rappels, icône)."
