/// Initialisation propre aux ordinateurs (Windows).
///
/// Sur téléphone ce fichier ne fait rien. Pour la version Windows, le workflow GitHub remplace son
/// contenu par `tool/windows/desktop_init.dart.txt` (base SQLite via FFI) et ajoute la dépendance
/// `sqflite_common_ffi` seulement dans le build Windows : le `pubspec.yaml` du dépôt reste inchangé.
Future<void> initDesktop() async {}
