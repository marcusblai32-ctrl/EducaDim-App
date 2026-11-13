import 'package:dio/dio.dart';
import '../db/cache_store.dart';
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
///  - quiz_submit       -> POST quiz-attempts/<id>/submit/ (idempotent, résultat mis en cache)
///  - quiz_offline_submit -> POST quizzes/<id>/offline-submit/ (quiz passé hors ligne, recorrigé par le serveur)
///  - chat_message      -> POST chat/rooms/<room_id>/messages/ (idempotent via client_id)
class ApiSyncGateway implements SyncGateway {
  ApiSyncGateway(this._api, [this._cache]);
  final ApiClient _api;
  final CacheStore? _cache;

  Future<PushOutcome> _post(String path,
      [Object? data, Future<void> Function(dynamic)? onOk]) async {
    try {
      final res = await _api.dio.post(path, data: data);
      final code = res.statusCode ?? 0;
      if (code == 200 || code == 201) {
        if (onOk != null) await onOk(res.data);
        return PushOutcome.synced;
      }
      return PushOutcome.retryLater;
    } on DioException catch (e) {
      final ex = mapDio(e);
      if (ex.isOffline) return PushOutcome.retryLater;
      final s = ex.statusCode ?? 0;
      if (s == 400 || s == 403 || s == 404 || s == 409) return PushOutcome.rejected;
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
      case 'chat_message':
        final room = item.payload['room_id'];
        final text = item.payload['contenu'];
        if (room is! int || text is! String) return Future.value(PushOutcome.rejected);
        return _post('chat/rooms/$room/messages/', {'contenu': text, 'client_id': item.id});
      case 'quiz_submit':
        final id = item.payload['attempt_id'];
        if (id is! int) return Future.value(PushOutcome.rejected);
        return _post(
          'quiz-attempts/$id/submit/',
          {'answers': item.payload['answers'] ?? const []},
          (data) async => _cache?.put('quiz:attempt:$id', data),
        );
      case 'quiz_offline_submit':
        final qid = item.payload['quiz_id'];
        final local = item.payload['local_id'];
        if (qid is! int || local is! int) return Future.value(PushOutcome.rejected);
        return _post(
          'quizzes/$qid/offline-submit/',
          {'started_at': item.payload['started_at'], 'answers': item.payload['answers'] ?? const []},
          (data) async => _cache?.put('quiz:attempt:$local', data),
        );
      default:
        return Future.value(PushOutcome.unavailable);
    }
  }
}
