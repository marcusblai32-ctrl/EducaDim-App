import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:educadim/core/db/outbox_repository.dart';
import 'package:educadim/core/network/api_client.dart';
import 'package:educadim/core/storage/token_store.dart';
import 'package:educadim/core/sync/sync_gateway.dart';
import 'package:educadim/features/courses/models.dart';
import 'package:educadim/features/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tokens extends TokenStore {
  @override
  Future<String?> get access async => 'a';
  @override
  Future<String?> get refresh async => null;
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

OutboxItem _item(String kind, Map<String, dynamic> p) => OutboxItem(
    id: 'x', kind: kind, payload: p, createdAt: DateTime.now(), attempts: 0);

ApiSyncGateway _gw(ResponseBody Function(RequestOptions) h, [List<String>? log]) {
  final dio = Dio(BaseOptions(baseUrl: 'https://t/api/v1/'))
    ..httpClientAdapter = _Adapter((o) {
      log?.add('${o.method} ${o.path}');
      return h(o);
    });
  return ApiSyncGateway(ApiClient(_Tokens(), onSessionExpired: () {}, dio: dio));
}

void main() {
  test('lesson_completed 201 -> synced, bon endpoint', () async {
    final log = <String>[];
    final g = _gw((o) => _json({'lesson_id': 4}, 201), log);
    expect(await g.push(_item('lesson_completed', {'lesson_id': 4})), PushOutcome.synced);
    expect(log, ['POST lessons/4/complete/']);
  });

  test('lesson_completed 200 (déjà fait) -> synced', () async {
    final g = _gw((o) => _json({'already_completed': true}, 200));
    expect(await g.push(_item('lesson_completed', {'lesson_id': 4})), PushOutcome.synced);
  });

  test('403 quiz requis -> rejected', () async {
    final g = _gw((o) => _json({'code': 'lesson_quiz_required'}, 403));
    expect(await g.push(_item('lesson_completed', {'lesson_id': 4})), PushOutcome.rejected);
  });

  test('coupure réseau -> retryLater', () async {
    final g = _gw((o) =>
        throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
    expect(await g.push(_item('lesson_completed', {'lesson_id': 4})), PushOutcome.retryLater);
  });

  test('notification_read -> POST notifications/<id>/read/', () async {
    final log = <String>[];
    final g = _gw((o) => _json({'lue': true}, 200), log);
    expect(await g.push(_item('notification_read', {'id': 9})), PushOutcome.synced);
    expect(log, ['POST notifications/9/read/']);
  });

  test('quiz_submit 201 -> synced, envoie les réponses', () async {
    final log = <String>[];
    Object? body;
    final g = _gw((o) {
      body = o.data;
      return _json({'attempt_id': 3, 'submitted': true}, 201);
    }, log);
    final out = await g.push(_item('quiz_submit', {
      'attempt_id': 3,
      'answers': [
        {'question_id': 1, 'reponse_ids': [10], 'texte': ''}
      ]
    }));
    expect(out, PushOutcome.synced);
    expect(log, ['POST quiz-attempts/3/submit/']);
    expect((body as Map)['answers'], isNotEmpty);
  });

  test('quiz_submit 400/409 -> rejected (ne bloque pas la file)', () async {
    final g = _gw((o) => _json({'detail': 'x'}, 400));
    expect(await g.push(_item('quiz_submit', {'attempt_id': 3})), PushOutcome.rejected);
  });

  test('chat_message -> POST du salon avec client_id', () async {
    final log = <String>[];
    Object? body;
    final g = _gw((o) {
      body = o.data;
      return _json({'id': 1}, 201);
    }, log);
    final out = await g.push(OutboxItem(
        id: 'uuid-1',
        kind: 'chat_message',
        payload: {'room_id': 4, 'contenu': 'Bonjour'},
        createdAt: DateTime.now(),
        attempts: 0));
    expect(out, PushOutcome.synced);
    expect(log, ['POST chat/rooms/4/messages/']);
    expect((body as Map)['client_id'], 'uuid-1');
    expect(body['contenu'], 'Bonjour');
  });

  test('chat_message sans salon (ancien chat local) -> rejected', () async {
    final g = _gw((o) => _json({}, 200));
    expect(await g.push(_item('chat_message', {'body': 'x'})), PushOutcome.rejected);
  });

  test('type inconnu -> unavailable', () async {
    final g = _gw((o) => _json({}, 200));
    expect(await g.push(_item('autre', {})), PushOutcome.unavailable);
  });

  test('AppNotification.fromJson', () {
    final n = AppNotification.fromJson({
      'id': 1,
      'type': 'badge',
      'titre': 'Bravo',
      'message': 'm',
      'lien': '',
      'lue': false,
      'date': '2026-01-02T10:00:00Z'
    });
    expect(n.lien, isNull);
    expect(n.lue, false);
    expect(n.read().lue, true);
  });

  test('ProgressSummary / ActivityItem', () {
    final p = ProgressSummary.fromJson({
      'lessons': [
        {'lesson_id': 1, 'course_id': 2}
      ],
      'courses': [
        {'course_id': 2, 'pourcentage': 50.0}
      ]
    });
    expect(p.lessonsDone, 1);
    expect(p.coursePct[2], 50.0);
    final a = ActivityItem.listFromJson({
      'results': [
        {'type': 'lecon_termine', 'label': 'Leçon terminée', 'description': 'd', 'date': null}
      ]
    });
    expect(a.single.label, 'Leçon terminée');
  });
}
