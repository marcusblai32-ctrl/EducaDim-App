import 'package:dio/dio.dart';

/// Erreur lisible par l'utilisateur, en français.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.isOffline = false, this.code});
  final String message;
  final int? statusCode;
  final bool isOffline;

  /// Code métier renvoyé par le serveur (ex. account_locked).
  final String? code;

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
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final detail = data is Map && data['detail'] is String
          ? data['detail'] as String
          : null;
      final code = data is Map && data['code'] is String
          ? data['code'] as String
          : null;
      if (status == 429) {
        return ApiException('Trop de tentatives. Patientez une minute.',
            statusCode: status, code: code);
      }
      if (status == 401) {
        return ApiException(detail ?? 'Session expirée. Reconnectez-vous.',
            statusCode: status, code: code);
      }
      if (status == 403) {
        return ApiException(detail ?? 'Accès refusé.', statusCode: status, code: code);
      }
      if (status == 400) {
        return ApiException(detail ?? 'Données invalides.', statusCode: status);
      }
      if (status == 404) {
        return ApiException('Ressource introuvable sur le serveur.', statusCode: status);
      }
      if (status != null && status >= 500) {
        return ApiException(
            'Le serveur est momentanément indisponible. Réessayez plus tard.',
            statusCode: status);
      }
    }
    return ApiException('Une erreur est survenue. Réessayez.');
  }

  @override
  String toString() => message;
}

/// 403 course_access_required : inscription ou abonnement nécessaire.
class CourseAccessRequired extends ApiException {
  CourseAccessRequired(super.message, {this.enrollmentStatus})
      : super(statusCode: 403, code: 'course_access_required');
  final String? enrollmentStatus;
}

/// 403 lesson_quiz_required : un quiz doit être réussi avant la leçon.
class LessonQuizRequired extends ApiException {
  LessonQuizRequired(super.message, this.quizIds)
      : super(statusCode: 403, code: 'lesson_quiz_required');
  final List<int> quizIds;
}

/// Fonctionnalité sans endpoint côté backend.
class ContractMissing implements Exception {
  ContractMissing(this.feature, this.needs);
  final String feature;
  final String needs;
  @override
  String toString() => '$feature : $needs';
}

/// Convertit une DioException en exception métier typée.
ApiException mapDio(Object e) {
  if (e is DioException && e.response?.statusCode == 403) {
    final d = e.response?.data;
    if (d is Map) {
      final detail = d['detail'] is String ? d['detail'] as String : 'Accès refusé.';
      if (d['code'] == 'course_access_required') {
        return CourseAccessRequired(detail,
            enrollmentStatus: d['enrollment_status'] as String?);
      }
      if (d['code'] == 'lesson_quiz_required') {
        final ids = (d['quiz_ids'] as List?)?.whereType<int>().toList() ?? <int>[];
        return LessonQuizRequired(detail, ids);
      }
    }
  }
  return ApiException.from(e);
}
