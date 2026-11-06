import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:educadim/core/db/app_database.dart';
import 'package:educadim/core/db/cache_store.dart';
import 'package:educadim/core/network/api_client.dart';
import 'package:educadim/core/network/api_exception.dart';
import 'package:educadim/core/storage/token_store.dart';
import 'package:educadim/features/courses/course_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Tokens extends TokenStore {
  @override
  Future<String?> get access async => 'a';
  @override
  Future<String?> get refresh async => 'r';
  @override
  Future<void> save({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async =>
      handler(o);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
    jsonEncode(body), status, headers: {
  Headers.contentTypeHeader: ['application/json']
});

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late CacheStore cache;

  setUp(() async {
    db = await AppDatabase.open(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    cache = CacheStore(db);
  });

  // Sans fermeture, sqflite réutilise la même base mémoire entre les tests
  // (singleInstance) et le cache d'un test pollue le suivant.
  tearDown(() => db.close());

  CourseRepository repo(ResponseBody Function(RequestOptions) h) {
    final dio = Dio(BaseOptions(baseUrl: 'https://t/api/v1/'))
      ..httpClientAdapter = _Adapter(h);
    return CourseRepository(
        ApiClient(_Tokens(), onSessionExpired: () {}, dio: dio), cache);
  }

  test('403 course_access_required devient CourseAccessRequired', () async {
    final r = repo((o) => _json({
          'detail': 'Inscription requise',
          'code': 'course_access_required',
          'enrollment_status': 'pending'
        }, 403));
    expect(r.curriculum(3), throwsA(isA<CourseAccessRequired>()));
  });

  test('403 lesson_quiz_required devient LessonQuizRequired', () async {
    final r = repo((o) =>
        _json({'detail': 'Quiz', 'code': 'lesson_quiz_required', 'quiz_ids': [4]}, 403));
    try {
      await r.lesson(1);
      fail('doit lever');
    } on LessonQuizRequired catch (e) {
      expect(e.quizIds, [4]);
    }
  });

  test('succès puis coupure réseau : lecture depuis le cache', () async {
    var online = true;
    final r = repo((o) {
      if (!online) {
        throw DioException(
            requestOptions: o, type: DioExceptionType.connectionError);
      }
      return _json({'count': 0, 'next': null, 'results': []}, 200);
    });
    final first = await r.catalog();
    expect(first.fromCache, false);
    online = false;
    final second = await r.catalog();
    expect(second.fromCache, true);
  });

  test('coupure réseau sans cache : erreur hors ligne', () async {
    final r = repo((o) =>
        throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
    expect(r.catalog(), throwsA(predicate((e) => e is ApiException && e.isOffline)));
  });
}
