import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/api_config.dart';
import '../../core/i18n/lang.dart';
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

  /// Défi de vérification en deux étapes en attente : {challenge_id, channel, target}.
  Map<String, dynamic>? pending2fa;

  ApiException _mapLoginError(Object e) {
    if (e is DioException && e.response?.statusCode == 404) {
      return ApiException(tr('Connexion impossible pour le moment. Réessayez plus tard.'),
          statusCode: 404);
    }
    if (e is DioException && e.response == null && e.type == DioExceptionType.unknown) {
      return ApiException(tr('Connexion impossible. Vérifiez votre Internet et réessayez.'),
          isOffline: true);
    }
    if (e is DioException) {
      final data = e.response?.data;
      final detail = data is Map && data['detail'] is String ? data['detail'] as String : null;
      if (e.response?.statusCode == 429 && data is Map && data['code'] == 'two_factor_wait') {
        return ApiException(detail ?? tr('Patientez avant de redemander un code.'),
            statusCode: 429);
      }
      if (e.response?.statusCode == 400 && detail != null) {
        return ApiException(detail, statusCode: 400);
      }
      if (e.response?.statusCode == 503 && detail != null) {
        return ApiException(detail, statusCode: 503);
      }
    }
    return ApiException.from(e);
  }

  Future<void> _finishLogin(dynamic d) async {
    final access = d is Map ? d[ApiContract.accessTokenKey] : null;
    if (access is! String) {
      throw ApiException(tr('Connexion impossible pour le moment. Réessayez plus tard.'));
    }
    final refresh = d[ApiContract.refreshTokenKey];
    await _tokens.save(access: access, refresh: refresh is String ? refresh : null);
    if (d['user'] is Map) {
      user = Map<String, dynamic>.from(d['user'] as Map);
      await _cache.put('me', user);
    }
    pending2fa = null;
    final id = identity;
    if (id != null) await onLoggedIn?.call(id);
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  /// Retourne true si un code de vérification est demandé (2FA), false si connecté.
  /// Lance ApiException (message traduit) en cas d'échec.
  Future<bool> login(String identifier, String password) async {
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
      if (d is Map && d['two_factor_required'] == true) {
        pending2fa = Map<String, dynamic>.from(d);
        return true;
      }
      await _finishLogin(d);
      return false;
    } catch (e) {
      throw _mapLoginError(e);
    }
  }

  Future<void> verify2fa(String code) async {
    final id = pending2fa?['challenge_id'];
    if (id == null) throw ApiException(tr('Connexion impossible pour le moment. Réessayez plus tard.'));
    try {
      final res = await api.dio.post(
        'auth/login/2fa/',
        data: {'challenge_id': id, 'code': code.trim()},
        options: Options(extra: {'noAuth': true}),
      );
      await _finishLogin(res.data);
    } catch (e) {
      final ex = _mapLoginError(e);
      if (ex.statusCode == 403 || ex.code == 'two_factor_expired') pending2fa = null;
      throw ex;
    }
  }

  Future<void> resend2fa() async {
    final id = pending2fa?['challenge_id'];
    if (id == null) return;
    try {
      final res = await api.dio.post(
        'auth/login/2fa/resend/',
        data: {'challenge_id': id},
        options: Options(extra: {'noAuth': true}),
      );
      if (res.data is Map) pending2fa = Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw _mapLoginError(e);
    }
  }

  void cancel2fa() => pending2fa = null;

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
