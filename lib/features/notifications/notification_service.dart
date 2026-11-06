
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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
  final String type;
  final String titre;
  final String message;
  final String? lien;
  final bool lue;
  final DateTime? date;

  AppNotification read() => AppNotification(
        id: id,
        type: type,
        titre: titre,
        message: message,
        lien: lien,
        lue: true,
        date: date,
      );

  factory AppNotification.fromJson(dynamic j) {
    final m = j is Map ? j : const {};

    String? s(String k) =>
        m[k] is String ? m[k] as String : null;

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

/// Gestion des notifications EducaDim.
///
/// Fonctionnalités :
/// - Chargement depuis l'API.
/// - Cache hors ligne.
/// - Marquage immédiat comme lu.
/// - Synchronisation via Outbox.
/// - Actualisation automatique.
/// - Réinitialisation lors du changement de compte.
class NotificationService extends ChangeNotifier {
  NotificationService(
    this._api,
    this._cache,
    this._outbox,
    this._sync,
  );

  final ApiClient _api;
  final CacheStore _cache;
  final OutboxRepository _outbox;
  final SyncService _sync;

  List<AppNotification> items = [];

  bool loading = false;
  bool fromCache = false;
  String? error;

  Timer? _timer;

  bool _disposed = false;
  bool _resetting = false;

  int get unread => items.where((n) => !n.lue).length;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Réinitialise les données en mémoire.
  ///
  /// Le cache persistant n'est pas supprimé ici :
  /// sa suppression dépend de la stratégie de UserDataGuard.
  void reset() {
    _resetting = true;

    items = [];
    loading = false;
    fromCache = false;
    error = null;

    _notify();

    _resetting = false;
  }

  /// Démarre le polling toutes les 90 secondes.
  void startPolling(bool Function() isLoggedIn) {
    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 90),
      (_) {
        if (!_disposed && !_resetting && isLoggedIn()) {
          unawaited(refresh(silent: true));
        }
      },
    );
  }

  /// Charge les notifications depuis le cache local.
  Future<void> loadCached() async {
    if (_disposed || _resetting) return;

    try {
      final c = await _cache.get('notifications');

      if (_disposed || _resetting) return;

      if (c is Map && c['items'] is List) {
        items = (c['items'] as List)
            .map(AppNotification.fromJson)
            .toList();

        fromCache = true;
        error = null;

        _notify();
      }
    } catch (_) {
      error = 'Impossible de charger les notifications locales.';
      _notify();
    }
  }

  /// Récupère les notifications dont la lecture
  /// est encore en attente de synchronisation.
  Future<Set<int>> _pendingReads() async {
    final pend = await _outbox.pending(limit: 500);

    return pend
        .where(
          (i) =>
              i.kind == 'notification_read' &&
              i.payload['id'] is int,
        )
        .map((i) => i.payload['id'] as int)
        .toSet();
  }

  /// Actualise les notifications depuis le serveur.
  Future<void> refresh({bool silent = false}) async {
    if (_disposed || _resetting) return;

    if (!silent) {
      loading = true;
      error = null;
      _notify();
    }

    try {
      final res = await _api.dio.get('notifications/');

      if (_disposed || _resetting) return;

      final data = res.data;

      final raw = data is Map && data['results'] is List
          ? data['results'] as List
          : <dynamic>[];

      final pend = await _pendingReads();

      if (_disposed || _resetting) return;

      items = raw
          .map(AppNotification.fromJson)
          .map(
            (n) => pend.contains(n.id) ? n.read() : n,
          )
          .toList();

      fromCache = false;
      error = null;

      await _cache.put(
        'notifications',
        {
          'items': items.map((n) => n.toJson()).toList(),
        },
      );
    } on DioException catch (e) {
      if (_disposed || _resetting) return;

      final ex = mapDio(e);

      if (ex.statusCode == 404) {
        error =
            'Les notifications ne sont pas encore disponibles sur le serveur '
            '(mise à jour du backend nécessaire).';
      } else if (items.isEmpty) {
        error = ex.message;
      }

      if (items.isNotEmpty) {
        fromCache = true;
      }
    } catch (_) {
      if (_disposed || _resetting) return;

      if (items.isEmpty) {
        error = 'Impossible de charger les notifications.';
      }

      if (items.isNotEmpty) {
        fromCache = true;
      }
    } finally {
      if (!_disposed && !_resetting) {
        loading = false;
        _notify();
      }
    }
  }

  /// Marque une notification comme lue.
  Future<void> markRead(AppNotification n) async {
    if (_disposed || n.lue) return;

    items = [
      for (final x in items)
        if (x.id == n.id) x.read() else x,
    ];

    _notify();

    await _cache.put(
      'notifications',
      {
        'items': items.map((x) => x.toJson()).toList(),
      },
    );

    await _outbox.enqueue(
      'notification_read',
      {'id': n.id},
      id: 'notif-read-${n.id}',
    );

    await _sync.refreshCount();

    unawaited(_sync.flush());
  }

  /// Marque toutes les notifications comme lues.
  Future<void> markAllRead() async {
    final unreadItems = List<AppNotification>.of(
      items.where((n) => !n.lue),
    );

    for (final n in unreadItems) {
      if (_disposed) return;
      await markRead(n);
    }
  }

  @override
  void dispose() {
    _disposed = true;

    _timer?.cancel();
    _timer = null;

    super.dispose();
  }
}
