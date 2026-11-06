import 'package:shared_preferences/shared_preferences.dart';
import 'app_database.dart';

/// Empêche qu'un autre compte voie les données locales du précédent
/// (téléphones partagés). Lors d'une connexion avec une identité différente,
/// on efface les caches et la progression locale. La file d'attente n'est PAS
/// effacée : ses éléments sont marqués par propriétaire et n'ont jamais été
/// envoyés avec un autre jeton ; ils repartent quand leur propriétaire revient.
class UserDataGuard {
  UserDataGuard(this._d, this._prefs);
  final AppDatabase _d;
  final SharedPreferences _prefs;
  static const _key = 'last_identity';

  /// Retourne true si les données locales ont été effacées.
  Future<bool> onLogin(String identity) async {
    final last = _prefs.getString(_key);
    await _prefs.setString(_key, identity);
    if (last == null || last == identity) return false;
    await wipe();
    return true;
  }

  Future<void> wipe() async {
    await _d.db.delete('api_cache');
    await _d.db.delete('local_progress');
    await _d.db.delete('offline_courses');
    await _d.db.delete('chat_messages');
    await _prefs.remove('last_lesson');
  }
}
