# Plateformes

| Plateforme | Workflow | Résultat |
|---|---|---|
| Android | `dezipe-ak-build.yml` | APK |
| Windows | `build-windows.yml` (lancement manuel) | `EducaDim-Windows.zip` (portable) + `EducaDim-Setup.exe` (installateur) |
| iOS | `build-ios.yml` (lancement manuel) | `EducaDim-unsigned.ipa` (non signé) |

* `pubspec.yaml` n'est jamais modifié : le build Windows ajoute `sqflite_common_ffi` (+ `sqlite3_flutter_libs`)
  uniquement dans l'exécuteur GitHub et remplace `lib/core/platform/desktop_init.dart` par
  `tool/windows/desktop_init.dart.txt`.
* Windows : pas de WebView intégrée, les vidéos s'ouvrent dans le navigateur du système ; pas de rappels programmés.
* iOS : l'IPA n'est pas signé. Pour l'installer il faut le signer (compte Apple Developer, AltStore, Sideloadly…).
