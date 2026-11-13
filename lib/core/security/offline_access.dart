import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/app_database.dart';
import '../network/api_client.dart';

/// Accès hors ligne = lié à l'abonnement / à l'achat.
///
/// * `access_until` (NULL = achat ou cours gratuit, sans fin) est enregistré avec chaque cours / fichier téléchargé.
/// * À la date de fin : le contenu téléchargé est BLOQUÉ (illisible, même hors ligne).
/// * 3 jours après la fin sans renouvellement : le contenu est SUPPRIMÉ du téléphone.
/// * L'horloge du téléphone ne peut pas être reculée pour tricher : on garde la date la plus récente jamais vue.
/// * Une vérification (un seul petit appel par cours) au plus une fois par 24 h quand on est en ligne ;
///   hors ligne, seule la date locale est contrôlée.
class OfflineAccess extends ChangeNotifier {
  OfflineAccess(this._db, this._api, this._prefs);
  final AppDatabase _db;
  final ApiClient _api;
  final SharedPreferences _prefs;

  static const grace = Duration(days: 3);
  static const _kSeen = 'edu_clock_seen_v1';
  static const _kCheck = 'edu_access_check_v1';

  /// Appelés quand le délai de grâce est dépassé : supprimer un cours / ses fichiers.
  Future<void> Function(int courseId)? purgeCourse;
  /// Clés du cache API d'un cours (pour les bloquer pendant le délai de grâce).
  Future<List<String>> Function(int courseId)? cacheKeysFor;

  final Set<int> _locked = {};
  final Set<String> _blocked = {};

  bool isLocked(int courseId) => _locked.contains(courseId);
  bool blocks(String cacheKey) => _blocked.contains(cacheKey);

  /// Heure « de confiance » : jamais en arrière de la dernière heure vue.
  DateTime now() {
    final dev = DateTime.now();
    final seen = DateTime.tryParse(_prefs.getString(_kSeen) ?? '');
    if (seen != null && seen.isAfter(dev)) return seen;
    _prefs.setString(_kSeen, dev.toIso8601String());
    return dev;
  }

  Future<List<Map<String, Object?>>> _rows() async {
    final a = await _db.db.rawQuery('SELECT course_id, access_until FROM offline_courses');
    final b = await _db.db.rawQuery(
        'SELECT course_id, access_until FROM downloads WHERE course_id IS NOT NULL');
    return [...a, ...b];
  }

  /// Recalcule les cours bloqués et supprime ceux dont le délai de grâce est dépassé.
  Future<void> sweep() async {
    final n = now();
    final until = <int, int?>{}; // course_id -> fin la plus lointaine (null = sans fin)
    for (final r in await _rows()) {
      final id = (r['course_id'] as num).toInt();
      final u = (r['access_until'] as num?)?.toInt();
      if (!until.containsKey(id)) {
        until[id] = u;
      } else if (until[id] != null) {
        until[id] = u == null ? null : (u > until[id]! ? u : until[id]);
      }
    }
    final lockedNow = <int>{};
    for (final e in until.entries) {
      final u = e.value;
      if (u == null) continue;
      final end = DateTime.fromMillisecondsSinceEpoch(u);
      if (n.isAfter(end.add(grace))) {
        await purgeCourse?.call(e.key);
      } else if (!n.isBefore(end)) {
        lockedNow.add(e.key);
      }
    }
    _blocked.clear();
    for (final id in lockedNow) {
      _blocked.addAll(await cacheKeysFor?.call(id) ?? const []);
    }
    _locked
      ..clear()
      ..addAll(lockedNow);
    notifyListeners();
  }

  /// Met à jour les dates de fin auprès du serveur : au plus une fois par 24 h, en ligne seulement.
  Future<void> refreshIfDue({bool force = false}) async {
    await sweep();
    final last = DateTime.tryParse(_prefs.getString(_kCheck) ?? '');
    if (!force && last != null && now().difference(last) < const Duration(hours: 24)) return;
    final ids = <int>{};
    for (final r in await _rows()) {
      ids.add((r['course_id'] as num).toInt());
    }
    if (ids.isEmpty) return;
    var reached = false;
    for (final id in ids) {
      try {
        final res = await _api.dio.get('courses/$id/access/');
        reached = true;
        final m = res.data is Map ? res.data as Map : const {};
        int? until;
        if (m['has_access'] != true) {
          until = now().millisecondsSinceEpoch; // accès retiré : bloqué maintenant, supprimé dans 3 jours
        } else if (m['expires_at'] is String) {
          until = DateTime.tryParse(m['expires_at'] as String)?.millisecondsSinceEpoch;
        }
        await setUntil(id, until);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404 || e.response?.statusCode == 403) {
          reached = true;
          await setUntil(id, now().millisecondsSinceEpoch);
        }
        // hors ligne : on garde la date locale
      }
    }
    if (reached) await _prefs.setString(_kCheck, now().toIso8601String());
    await sweep();
  }

  Future<void> setUntil(int courseId, int? until) async {
    await _db.db.update('offline_courses', {'access_until': until}, where: 'course_id = ?', whereArgs: [courseId]);
    await _db.db.update('downloads', {'access_until': until}, where: 'course_id = ?', whereArgs: [courseId]);
  }

  /// Lit l'accès actuel d'un cours (au moment du téléchargement).
  Future<int?> fetchUntil(int courseId) async {
    final res = await _api.dio.get('courses/$courseId/access/');
    final m = res.data is Map ? res.data as Map : const {};
    if (m['has_access'] != true) throw StateError('no_access');
    return m['expires_at'] is String ? DateTime.tryParse(m['expires_at'] as String)?.millisecondsSinceEpoch : null;
  }

  void reset() {
    _locked.clear();
    _blocked.clear();
    _prefs.remove(_kCheck);
    notifyListeners();
  }

  // Utilitaire de test/debug.
  @visibleForTesting
  String debugState() => jsonEncode({'locked': _locked.toList(), 'blocked': _blocked.length});
}
