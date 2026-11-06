import 'package:dio/dio.dart';

/// Erreur lisible par l'utilisateur, en français.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.isOffline = false});
  final String message;
  final int? statusCode;
  final bool isOffline;

  factory ApiException.from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ApiException(
            'Connexion impossible. Vérifiez votre Internet et réessayez.',
            isOffline: true,
          );
        default:
          break;
      }
      final code = e.response?.statusCode;
      if (code == 400 || code == 401) {
        return ApiException('Identifiants incorrects ou requête invalide.',
            statusCode: code);
      }
      if (code == 403) return ApiException('Accès refusé.', statusCode: code);
      if (code == 404) {
        return ApiException('Ressource introuvable sur le serveur.',
            statusCode: code);
      }
      if (code != null && code >= 500) {
        return ApiException(
            'Le serveur est momentanément indisponible. Réessayez plus tard.',
            statusCode: code);
      }
    }
    return ApiException('Une erreur est survenue. Réessayez.');
  }

  @override
  String toString() => message;
}

/// Fonctionnalité dont le contrat backend n'est pas encore confirmé.
class ContractMissing implements Exception {
  ContractMissing(this.feature, this.needs);
  final String feature;
  final String needs;
  @override
  String toString() => '$feature : $needs';
}
