import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import '../network/api_client.dart';

/// Notifications « au passage » : AUCUN sondage répété.
///
/// * Chaque réponse du serveur porte l'en-tête `X-Notif: <non lues>,<dernier id>` (calculé côté serveur sans requête
///   supplémentaire pour l'application). Si la valeur change, les notifications sont rechargées (voir [onHeader]).
/// * Un seul appel `pulse/` à l'ouverture de l'application, puis au retour au premier plan seulement si le dernier
///   a plus de 15 minutes.
/// * Les rapports locaux (rapèls) n'utilisent pas du tout le serveur.
class PulseService {
  PulseService(this._api, this._loggedIn, {this.onNotifications});
  final ApiClient _api;
  final bool Function() _loggedIn;
  final Future<void> Function()? onNotifications;

  AppLifecycleListener? _lifecycle;
  bool _busy = false;
  String? _seen;
  DateTime? _last;

  void start() {
    _lifecycle ??= AppLifecycleListener(onResume: () {
      final last = _last;
      if (last == null || DateTime.now().difference(last) > const Duration(minutes: 15)) tick();
    });
    if (_loggedIn()) tick();
  }

  /// Changement de compte ou déconnexion : on oublie l'état précédent.
  void reset() {
    _seen = null;
    _last = null;
  }

  /// Appelé pour chaque réponse du serveur (intercepteur Dio).
  void onHeader(String? value) {
    if (value == null || !_loggedIn()) return;
    if (_seen == null) {
      _seen = value;
      return;
    }
    if (value != _seen) {
      _seen = value;
      onNotifications?.call();
    }
  }

  Future<void> tick() async {
    if (_busy || !_loggedIn()) return;
    _busy = true;
    try {
      await _api.dio.get('pulse/');
      _last = DateTime.now();
      await onNotifications?.call();
    } on DioException catch (_) {
      // hors ligne : on réessaiera plus tard
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _lifecycle?.dispose();
  }
}
