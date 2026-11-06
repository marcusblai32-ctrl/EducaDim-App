import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/token_store.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthController extends ChangeNotifier {
  AuthController(this._tokens);
  final TokenStore _tokens;
  late ApiClient api; // injecté après création (dépendance circulaire)

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  Future<void> init() async {
    final t = await _tokens.access;
    _status = t == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
    notifyListeners();
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
      _status = AuthStatus.authenticated;
      notifyListeners();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Efface uniquement les jetons : la file de synchronisation locale est
  /// conservée pour ne perdre aucune progression non envoyée.
  Future<void> logout() async {
    await _tokens.clear();
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void expire() {
    if (_status == AuthStatus.unauthenticated) return;
    logout();
  }
}
