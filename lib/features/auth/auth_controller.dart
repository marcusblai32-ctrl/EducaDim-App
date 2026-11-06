import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/db/cache_store.dart';
import '../../core/storage/token_store.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthController extends ChangeNotifier {
  AuthController(this._tokens, this._cache);
  final TokenStore _tokens;
  final CacheStore _cache;
  late ApiClient api; // injecté après création (dépendance circulaire)

  AuthStatus _status = AuthStatus.unknown;
  Map<String, dynamic>? user; // objet `user` du backend (login et GET me/)
  String get firstName => (user?['first_name'] as String?) ?? '';
  String get fullName => (user?['full_name'] as String?) ?? '';
  String get email => (user?['email'] as String?) ?? '';

  /// Identité stable du compte (marque la file d'attente et détecte le changement de compte).
  String? get identity {
    final u = user;
    if (u == null) return null;
    final v = u['id'] ?? u['user_id'] ?? u['email'];
    return v?.toString();
  }

  /// Appelé après une connexion réussie (ex. purge des données d'un autre compte).
  Future<void> Function(String identity)? onLoggedIn;

  AuthStatus get status => _status;

  Future<void> init() async {
    final t = await _tokens.access;
    _status = t == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
    if (t != null) {
      final cached = await _cache.get('me');
      if (cached is Map) user = Map<String, dynamic>.from(cached);
    }
    notifyListeners();
    if (t != null) refreshUser();
  }

  /// GET /me/ ; en cas d'échec réseau on garde le dernier profil connu.
  Future<void> refreshUser() async {
    try {
      final res = await api.dio.get('me/');
      if (res.data is Map) {
        user = Map<String, dynamic>.from(res.data as Map);
        await _cache.put('me', user);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Lance ApiException (message en français) en cas d'échec.
  Future<void> login(String identifier, String password) async {
    try {
      final res = await api.dio.post(
        ApiContract.loginPath,
        data: {
          ApiContract.loginIdentifierField: identifier.trim(),
          ApiContract.loginPasswordField: password,
        },
        options: Options(extra: {'noAuth': true}),
      );
      final d = res.data;
      final access = d is Map ? d[ApiContract.accessTokenKey] : null;
      if (access is! String) {
        throw ApiException(
            'Réponse de connexion inattendue : format du jeton à vérifier '
            '(voir docs/API_CONTRACT.md).');
      }
      final refresh = d[ApiContract.refreshTokenKey];
      await _tokens.save(
          access: access, refresh: refresh is String ? refresh : null);
      if (d['user'] is Map) {
        user = Map<String, dynamic>.from(d['user'] as Map);
        await _cache.put('me', user);
      }
      final id = identity;
      if (id != null) await onLoggedIn?.call(id);
      _status = AuthStatus.authenticated;
      notifyListeners();
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        throw ApiException(
            'API mobile introuvable (erreur 404). Le serveur n’a probablement '
            'pas encore été mis à jour avec l’application « mobile_api » : '
            'redéployez le backend sur Render.',
            statusCode: 404);
      }
      if (e is DioException && e.response == null && e.type == DioExceptionType.unknown) {
        throw ApiException(
            'Connexion impossible (${e.error ?? 'erreur réseau'}). '
            'Vérifiez Internet ; si le problème persiste, réinstallez la dernière version de l’application.',
            isOffline: true);
      }
      throw ApiException.from(e);
    }
  }

  /// Teste le serveur sans identifiants et explique le résultat en français.
  Future<String> diagnose() async {
    try {
      final res = await api.dio.get('courses/',
          options: Options(extra: {'noAuth': true}, validateStatus: (_) => true));
      final code = res.statusCode ?? 0;
      if (code == 401 || code == 403) {
        return '✅ Serveur API joignable (réponse $code attendue sans connexion). '
            'Le problème vient des identifiants.';
      }
      if (code == 404) {
        return '❌ Erreur 404 : l’API mobile n’est pas déployée sur le serveur. '
            'Redéployez le backend (avec mobile_api) sur Render.';
      }
      if (code >= 500) return '⚠️ Le serveur répond avec une erreur $code. Réessayez plus tard.';
      return 'Réponse inattendue du serveur : $code.';
    } on DioException catch (e) {
      return '❌ Impossible de joindre ${ApiConfig.baseUrl} '
          '(${e.type.name}). Vérifiez Internet, attendez 1 minute (le serveur '
          'gratuit se réveille) puis réessayez.';
    }
  }

  /// Efface uniquement les jetons : la file de synchronisation locale est
  /// conservée pour ne perdre aucune progression non envoyée.
  Future<void> logout() async {
    await _tokens.clear();
    user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void expire() {
    if (_status == AuthStatus.unauthenticated) return;
    logout();
  }
}
