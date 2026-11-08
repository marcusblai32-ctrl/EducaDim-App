import 'dart:async';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../i18n/lang.dart';
import '../storage/token_store.dart';

/// Client HTTP : ajoute le jeton, rafraîchit une seule fois en cas de 401
/// (les requêtes concurrentes attendent le même rafraîchissement), puis
/// signale l'expiration de session si le refresh échoue.
class ApiClient {
  ApiClient(this._tokens, {required this.onSessionExpired, Dio? dio})
      : dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: ApiConfig.connectTimeout,
              receiveTimeout: ApiConfig.receiveTimeout,
              headers: {'Accept': 'application/json'},
            )) {
    this.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) async {
        o.headers['Accept-Language'] = Lang.instance.code; // contenu des cours dans la langue choisie
        if (o.extra['noAuth'] != true) {
          final t = await _tokens.access;
          if (t != null) o.headers['Authorization'] = 'Bearer $t';
        }
        h.next(o);
      },
      onError: (e, h) async {
        final req = e.requestOptions;
        final is401 = e.response?.statusCode == 401;
        if (!is401 ||
            req.extra['noAuth'] == true ||
            req.extra['retried'] == true) {
          return h.next(e);
        }
        final ok = await _refresh();
        if (!ok) {
          onSessionExpired();
          return h.next(e);
        }
        try {
          req.extra['retried'] = true;
          final t = await _tokens.access;
          req.headers['Authorization'] = 'Bearer $t';
          h.resolve(await this.dio.fetch(req));
        } on DioException catch (e2) {
          h.next(e2);
        }
      },
    ));
  }

  final Dio dio;
  final TokenStore _tokens;
  final void Function() onSessionExpired;
  Completer<bool>? _refreshing;

  Future<bool> _refresh() {
    final running = _refreshing;
    if (running != null) return running.future;
    final c = _refreshing = Completer<bool>();
    () async {
      try {
        final r = await _tokens.refresh;
        if (r == null) {
          c.complete(false);
          return;
        }
        final res = await dio.post(
          ApiContract.refreshPath,
          data: {ApiContract.refreshTokenKey: r},
          options: Options(extra: {'noAuth': true}),
        );
        final data = res.data;
        final a = data is Map ? data[ApiContract.accessTokenKey] : null;
        if (a is! String) {
          c.complete(false);
          return;
        }
        final nr = data[ApiContract.refreshTokenKey];
        await _tokens.save(access: a, refresh: nr is String ? nr : null);
        c.complete(true);
      } catch (_) {
        c.complete(false);
      } finally {
        _refreshing = null;
      }
    }();
    return c.future;
  }
}
