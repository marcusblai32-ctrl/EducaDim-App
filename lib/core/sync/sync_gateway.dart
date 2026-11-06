import 'package:dio/dio.dart';
import '../db/outbox_repository.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

enum PushOutcome {
  /// Le serveur a confirmé la réception.
  synced,

  /// Échec temporaire (réseau, 5xx) : on réessaiera.
  retryLater,

  /// Le serveur refuse définitivement (ex. quiz requis) : l'élément est
  /// conservé comme « refusé » et ne bloque plus la file.
  rejected,

  /// Aucun endpoint pour ce type d'opération : l'élément reste en attente.
  unavailable,
}

/// Point d'intégration unique entre la file locale et le backend Django.
abstract class SyncGateway {
  Future<PushOutcome> push(OutboxItem item);
}

/// Implémentation par défaut (tests) : aucun endpoint.
class UnconfiguredGateway implements SyncGateway {
  @override
  Future<PushOutcome> push(OutboxItem item) async => PushOutcome.unavailable;
}

/// Passerelle réelle :
///  - lesson_completed  -> POST lessons/<id>/complete/ (idempotent côté serveur)
///  - notification_read -> POST notifications/<id>/read/ (idempotent)
///  - chat_message      -> pas d'endpoint : reste en attente
class ApiSyncGateway implements SyncGateway {
  ApiSyncGateway(this._api);
  final ApiClient _api;

  Future<PushOutcome> _post(String path, [Object? data]) async {
    try {
      final res = await _api.dio.post(path, data: data);
      final code = res.statusCode ?? 0;
      return (code == 200 || code == 201) ? PushOutcome.synced : PushOutcome.retryLater;
    } on DioException catch (e) {
      final ex = mapDio(e);
      if (ex.isOffline) return PushOutcome.retryLater;
      final s = ex.statusCode ?? 0;
      if (s == 403 || s == 404) return PushOutcome.rejected;
      return PushOutcome.retryLater; // 401, 5xx, etc.
    }
  }

  @override
  Future<PushOutcome> push(OutboxItem item) {
    switch (item.kind) {
      case 'lesson_completed':
        final id = item.payload['lesson_id'];
        if (id is! int) return Future.value(PushOutcome.rejected);
        return _post('lessons/$id/complete/', {
          'client_id': item.id,
          'completed_at': item.payload['completed_at'],
        });
      case 'notification_read':
        final id = item.payload['id'];
        if (id is! int) return Future.value(PushOutcome.rejected);
        return _post('notifications/$id/read/');
      default:
        return Future.value(PushOutcome.unavailable);
    }
  }
}
