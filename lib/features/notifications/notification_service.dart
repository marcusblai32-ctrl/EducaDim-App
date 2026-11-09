import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/i18n/lang.dart';
import '../../core/alerts/alert_service.dart';
import '../../core/db/cache_store.dart';
import '../../core/db/outbox_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/sync/sync_service.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.titre,
    required this.message,
    this.lien,
    required this.lue,
    this.date,
  });
  final int id;
  final String type, titre, message;
  final String? lien;
  final bool lue;
  final DateTime? date;

  AppNotification read() => AppNotification(
      id: id, type: type, titre: titre, message: message, lien: lien, lue: true, date: date);

  factory AppNotification.fromJson(dynamic j) {
    final m = j is Map ? j : const {};
    String? s(String k) => m[k] is String ? m[k] as String : null;
    return AppNotification(
      id: m['id'] is int ? m['id'] as int : 0,
      type: s('type') ?? 'systeme',
      titre: s('titre') ?? '',
      message: s('message') ?? '',
      lien: (s('lien') ?? '').isEmpty ? null : s('lien'),
      lue: m['lue'] == true,
      date: DateTime.tryParse(s('date') ?? '')?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'titre': titre,
        'message': message,
        'lien': lien,
        'lue': lue,
        'date': date?.toUtc().toIso8601String(),
      };
}

/// Notifications : lecture via l'API (avec cache hors ligne), marquage « lu »
/// immédiat en local puis envoyé via la file d'attente (idempotent).
/// Pas de push FCM : l'app interroge le serveur (au lancement, après
/// synchronisation et toutes les 90 s quand elle est ouverte).
class NotificationService extends ChangeNotifier {
  NotificationService(this._api, this._cache, this._outbox, this._sync);
  final ApiClient _api;
  final CacheStore _cache;
  final OutboxRepository _outbox;
  final SyncService _sync;

  List<AppNotification> items = [];
  bool loading = false;
  bool fromCache = false;
  String? error;
  Timer? _timer;
  final Set<int> _seen = {};
  bool _baseline = false;

  int get unread => items.where((n) => !n.lue).length;

  void startPolling(bool Function() isLoggedIn) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (isLoggedIn()) refresh(silent: true);
    });
  }

  Future<void> loadCached() async {
    final c = await _cache.get('notifications');
    if (c is Map && c['items'] is List) {
      items = (c['items'] as List).map(AppNotification.fromJson).toList();
      fromCache = true;
      notifyListeners();
    }
  }

  Future<Set<int>> _pendingReads() async {
    final pend = await _outbox.pending(limit: 500);
    return pend
        .where((i) => i.kind == 'notification_read' && i.payload['id'] is int)
        .map((i) => i.payload['id'] as int)
        .toSet();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final res = await _api.dio.get('notifications/');
      final data = res.data;
      final raw = data is Map && data['results'] is List ? data['results'] as List : <dynamic>[];
      final pend = await _pendingReads();
      items = raw.map(AppNotification.fromJson).map((n) => pend.contains(n.id) ? n.read() : n).toList();
      fromCache = false;
      error = null;
      // Son : nouvelles notifications non lues apparues depuis la dernière actualisation.
      final fresh = items.where((n) => !n.lue && !_seen.contains(n.id)).toList();
      if (_baseline && fresh.isNotEmpty) {
        if (fresh.length == 1) {
          AlertService.instance.notify(fresh.first.titre, fresh.first.message);
        } else {
          AlertService.instance.notify(tr('Nouvelles notifications'),
              tr('{n} nouvelles notifications', {'n': fresh.length}));
        }
      }
      for (final n in items) {
        _seen.add(n.id);
      }
      _baseline = true;
      await _cache.put('notifications', {'items': items.map((n) => n.toJson()).toList()});
    } on DioException catch (e) {
      final ex = mapDio(e);
      if (ex.statusCode == 404) {
        error = tr('Cette fonctionnalité n’est pas disponible pour le moment.');
      } else if (items.isEmpty) {
        error = ex.message;
      }
      if (items.isNotEmpty) fromCache = true;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(AppNotification n) async {
    if (n.lue) return;
    items = [for (final x in items) x.id == n.id ? x.read() : x];
    notifyListeners();
    await _cache.put('notifications', {'items': items.map((x) => x.toJson()).toList()});
    await _outbox.enqueue('notification_read', {'id': n.id}, id: 'notif-read-${n.id}');
    await _sync.refreshCount();
    unawaited(_sync.flush());
  }

  Future<void> markAllRead() async {
    for (final n in List.of(items.where((n) => !n.lue))) {
      await markRead(n);
    }
  }

  /// Vide la liste (changement de compte).
  void reset() {
    items = [];
    fromCache = false;
    error = null;
    _seen.clear();
    _baseline = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
