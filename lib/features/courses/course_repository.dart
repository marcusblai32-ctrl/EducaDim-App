import '../../core/network/api_exception.dart';

/// Couche isolée du catalogue et des inscriptions.
/// Aucun endpoint de cours n'a pu être confirmé : l'implémentation par défaut
/// lève ContractMissing. Remplacez-la par une implémentation Dio dès que le
/// contrat JSON réel est validé (docs/API_CONTRACT.md).
abstract class CourseRepository {
  Future<List<Map<String, dynamic>>> catalog();
  Future<List<Map<String, dynamic>>> myEnrollments();
}

class UnconfiguredCourseRepository implements CourseRepository {
  @override
  Future<List<Map<String, dynamic>>> catalog() => throw ContractMissing(
      'Catalogue des cours', 'endpoint de liste des cours non confirmé');

  @override
  Future<List<Map<String, dynamic>>> myEnrollments() => throw ContractMissing(
      'Mes cours', 'endpoint des inscriptions non confirmé');
}
