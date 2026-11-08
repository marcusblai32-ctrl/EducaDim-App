import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../db/outbox_repository.dart';
import '../i18n/lang.dart';
import 'sync_gateway.dart';

/// Vide la file d'attente dès que la connexion revient.
/// Indépendant de l'interface (aucun import de widget).
class SyncService extends ChangeNotifier {
  SyncService(this._outbox, this._gateway, [Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final OutboxRepository _outbox;
  final SyncGateway _gateway;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Appelé après confirmation serveur d'un élément.
  void Function(OutboxItem item)? onItemSynced;

  /// Appelé quand le serveur refuse définitivement un élément.
  void Function(OutboxItem item)? onItemRejected;

  /// Exécuté après l'envoi (ex. récupérer la progression du serveur).
  Future<void> Function()? afterFlush;

  /// Identité du compte connecté ; les éléments d'un autre compte restent en attente.
  String? Function()? currentOwner;

  bool _syncing = false;
  bool _online = true;
  int _pending = 0;
  String? _note;

  bool get syncing => _syncing;
  bool get online => _online;
  int get pending => _pending;

  /// Explication affichable si des éléments restent en attente.
  String? get note => _note;

  Future<void> start() async {
    final now = await _connectivity.checkConnectivity();
    _online = now.any((r) => r != ConnectivityResult.none);
    _sub = _connectivity.onConnectivityChanged.listen((r) {
      final on = r.any((x) => x != ConnectivityResult.none);
      final back = on && !_online;
      _online = on;
      notifyListeners();
      if (back) flush();
    });
    await refreshCount();
    if (_online) unawaited(flush());
  }

  Future<void> refreshCount() async {
    _pending = await _outbox.pendingCount();
    notifyListeners();
  }

  /// Un seul flush à la fois ; reprend automatiquement les éléments restants.
  Future<void> flush() async {
    if (_syncing || !_online) return;
    _syncing = true;
    _note = null;
    notifyListeners();
    try {
      for (final item in await _outbox.pending()) {
        final owner = item.payload['_owner'];
        if (owner != null && owner != currentOwner?.call()) continue;
        PushOutcome out;
        try {
          out = await _gateway.push(item);
        } catch (e) {
          await _outbox.markFailed(item.id, e.toString());
          _note = tr('Connexion instable : nouvel essai automatique plus tard.');
          break;
        }
        if (out == PushOutcome.synced) {
          await _outbox.markSynced(item.id);
          onItemSynced?.call(item);
        } else if (out == PushOutcome.rejected) {
          await _outbox.markRejected(item.id, 'rejected');
          onItemRejected?.call(item);
          _note = tr('Une action n’a pas pu être validée (accès ou quiz requis).');
        } else if (out == PushOutcome.unavailable) {
          // Type d'opération non pris en charge : conservé tel quel, sans bruit pour l'utilisateur.
        } else {
          await _outbox.markFailed(item.id, 'retry');
          _note = tr('Connexion instable : nouvel essai automatique plus tard.');
          break;
        }
      }
      await _outbox.purgeSynced();
      try {
        await afterFlush?.call();
      } catch (_) {}
    } finally {
      _syncing = false;
      await refreshCount();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
