import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

/// Avis de l'utilisateur sur l'application (note 1–5 + commentaire).
/// Rappel à CHAQUE ouverture tant que l'utilisateur n'a pas répondu.
class ReviewService extends ChangeNotifier {
  ReviewService(this._api);
  final ApiClient _api;

  bool enabled = false;
  bool answered = false;
  int? stars;
  String comment = '';
  bool loaded = false;

  /// Un seul rappel par ouverture de l'application.
  bool promptedThisLaunch = false;

  bool get shouldPrompt => loaded && enabled && !answered && !promptedThisLaunch;

  Future<void> load() async {
    try {
      final res = await _api.dio.get('avis/');
      final d = res.data is Map ? res.data as Map : const {};
      enabled = d['enabled'] == true;
      answered = d['answered'] == true;
      stars = d['stars'] is int ? d['stars'] as int : null;
      comment = d['comment'] is String ? d['comment'] as String : '';
      loaded = true;
    } on DioException {
      // Hors ligne : on ne dérange pas l'utilisateur, on réessaiera à la prochaine ouverture.
    }
    notifyListeners();
  }

  Future<void> submit(int stars, String comment) async {
    try {
      final res = await _api.dio.post('avis/', data: {'stars': stars, 'comment': comment.trim()});
      final d = res.data is Map ? res.data as Map : const {};
      answered = d['answered'] == true;
      this.stars = stars;
      this.comment = comment.trim();
      notifyListeners();
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  void markPrompted() => promptedThisLaunch = true;

  void reset() {
    enabled = false;
    answered = false;
    stars = null;
    comment = '';
    loaded = false;
    notifyListeners();
  }
}
