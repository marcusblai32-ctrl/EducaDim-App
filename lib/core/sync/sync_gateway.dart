import '../db/outbox_repository.dart';

enum PushOutcome {
  /// Le serveur a confirmé la réception.
  synced,

  /// Échec temporaire (réseau, 5xx) : on réessaiera.
  retryLater,

  /// Aucun endpoint confirmé pour ce type d'opération : on ne simule rien,
  /// l'élément reste en attente.
  unavailable,
}

/// Point d'intégration unique entre la file locale et le backend Django.
/// Implémentez `push` dès que les endpoints correspondants sont confirmés
/// (voir docs/API_CONTRACT.md).
abstract class SyncGateway {
  Future<PushOutcome> push(OutboxItem item);
}

/// Implémentation par défaut : aucun endpoint confirmé.
class UnconfiguredGateway implements SyncGateway {
  @override
  Future<PushOutcome> push(OutboxItem item) async => PushOutcome.unavailable;
}
