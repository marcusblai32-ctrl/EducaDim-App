import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../config/api_config.dart';
import '../i18n/lang.dart';
import '../network/api_client.dart';
import '../storage/token_store.dart';
import 'alert_service.dart';

const _task = 'educadim-poll';
const kFgAliveKey = 'fg_alive'; // horodatage écrit par l'app quand elle est ouverte
const _seenNotifKey = 'bg_seen_notif';
const _seenChatPrefix = 'bg_seen_chat_';
const _baselineKey = 'bg_baseline';

/// Point d'entrée exécuté par Android (même application fermée), environ toutes les 15 min.
/// Pas de FCM : on interroge le serveur et on affiche une notification locale
/// (bulle + son) pour les nouvelles notifications et les nouveaux messages.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      return await _poll();
    } catch (_) {
      return true; // ne jamais bloquer la planification
    }
  });
}

Future<bool> _poll() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  await Lang.instance.init(prefs);
  final tokens = TokenStore();
  if (await tokens.access == null) return true;

  final api = ApiClient(tokens, onSessionExpired: () {});
  final alive = prefs.getInt(kFgAliveKey) ?? 0;
  final appOpen = DateTime.now().millisecondsSinceEpoch - alive < 4 * 60 * 1000;
  final baseline = prefs.getBool(_baselineKey) ?? false;
  // Application ouverte : elle alerte déjà elle-même ; on ne fait que mémoriser l'état.
  final silent = appOpen || !baseline;

  await AlertService.instance.init(prefs);
  var lastNotif = prefs.getInt(_seenNotifKey) ?? 0;
  var maxNotif = lastNotif;
  final fresh = <Map>[];
  try {
    final res = await api.dio.get('notifications/');
    final raw = res.data is Map && res.data['results'] is List ? res.data['results'] as List : [];
    for (final n in raw) {
      if (n is! Map || n['id'] is! int) continue;
      final id = n['id'] as int;
      if (id > maxNotif) maxNotif = id;
      if (id > lastNotif && n['lue'] != true) fresh.add(n);
    }
  } on DioException {
    return true;
  }
  await prefs.setInt(_seenNotifKey, maxNotif);
  if (!silent && fresh.isNotEmpty) {
    if (fresh.length == 1) {
      await AlertService.instance.notify(
          (fresh.first['titre'] ?? '').toString(), (fresh.first['message'] ?? '').toString());
    } else {
      await AlertService.instance.notify(
          tr('Nouvelles notifications'), tr('{n} nouvelles notifications', {'n': fresh.length}));
    }
  }

  try {
    final res = await api.dio.get('chat/rooms/');
    final rooms = res.data is Map && res.data['rooms'] is List ? res.data['rooms'] as List : [];
    for (final r in rooms) {
      if (r is! Map || r['id'] is! int) continue;
      final last = r['last_message'] is Map ? r['last_message'] as Map : null;
      final at = DateTime.tryParse((last?['created_at'] ?? '').toString());
      if (last == null || at == null) continue;
      final key = '$_seenChatPrefix${r['id']}';
      final prev = DateTime.tryParse(prefs.getString(key) ?? '');
      if (prev == null || at.isAfter(prev)) {
        await prefs.setString(key, at.toUtc().toIso8601String());
        if (!silent && last['mine'] != true) {
          await AlertService.instance.notify(tr('Nouveau message'),
              '${r['titre'] ?? ''} — ${last['user_name'] ?? ''}: ${last['contenu'] ?? ''}');
        }
      }
    }
  } on DioException {
    // ignore : réessai au prochain passage
  }
  await prefs.setBool(_baselineKey, true);
  return true;
}

class BackgroundAlerts {
  static bool _init = false;

  static Future<void> start() async {
    try {
      if (!_init) {
        await Workmanager().initialize(backgroundDispatcher);
        _init = true;
      }
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await Workmanager().cancelAll();
    } catch (_) {}
  }

  /// Appelé périodiquement quand l'application est ouverte.
  static Future<void> markForeground(SharedPreferences prefs) =>
      prefs.setInt(kFgAliveKey, DateTime.now().millisecondsSinceEpoch);
}
