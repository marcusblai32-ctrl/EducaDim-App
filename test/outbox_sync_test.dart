import 'package:educadim/core/db/app_database.dart';
import 'package:educadim/core/db/outbox_repository.dart';
import 'package:educadim/core/db/user_data_guard.dart';
import 'package:educadim/core/sync/sync_gateway.dart';
import 'package:educadim/core/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Gw implements SyncGateway {
  _Gw(this.outcome);
  PushOutcome outcome;
  final pushed = <String>[];
  @override
  Future<PushOutcome> push(OutboxItem item) async {
    pushed.add(item.id);
    return outcome;
  }
}

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late OutboxRepository outbox;

  setUp(() async {
    db = await AppDatabase.open(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    outbox = OutboxRepository(db);
  });
  tearDown(() => db.close());

  test('enqueue avec le même id ne crée pas de doublon', () async {
    await outbox.enqueue('progress', {'a': 1}, id: 'x');
    await outbox.enqueue('progress', {'a': 2}, id: 'x');
    expect(await outbox.pendingCount(), 1);
  });

  test('élément non confirmé reste en attente (jamais supprimé)', () async {
    await outbox.enqueue('chat_message', {'body': 'salut'}, id: 'm1');
    final gw = _Gw(PushOutcome.unavailable);
    final sync = SyncService(outbox, gw);
    await sync.flush();
    expect(await outbox.pendingCount(), 1);
    expect(sync.note, isNotNull);
  });

  test('élément confirmé est marqué synchronisé et notifié', () async {
    await outbox.enqueue('chat_message', {'body': 'salut'}, id: 'm1');
    final sync = SyncService(outbox, _Gw(PushOutcome.synced));
    String? seen;
    sync.onItemSynced = (i) => seen = i.id;
    await sync.flush();
    expect(await outbox.pendingCount(), 0);
    expect(seen, 'm1');
  });

  test('retryLater incrémente les tentatives et conserve l\'élément', () async {
    await outbox.enqueue('progress', {}, id: 'p1');
    final sync = SyncService(outbox, _Gw(PushOutcome.retryLater));
    await sync.flush();
    final items = await outbox.pending();
    expect(items.single.attempts, 1);
  });

  test('un élément d\'un autre compte n\'est jamais envoyé avec le jeton courant', () async {
    outbox.ownerProvider = () => 'compte-A';
    await outbox.enqueue('lesson_completed', {'lesson_id': 1}, id: 'a1');
    final gw = _Gw(PushOutcome.synced);
    final sync = SyncService(outbox, gw)..currentOwner = () => 'compte-B';
    await sync.flush();
    expect(gw.pushed, isEmpty);
    expect(await outbox.pendingCount(), 1); // conservé pour son propriétaire

    sync.currentOwner = () => 'compte-A';
    await sync.flush();
    expect(gw.pushed, ['a1']);
    expect(await outbox.pendingCount(), 0);
  });

  test('UserDataGuard : purge au changement de compte, pas pour le même compte', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final guard = UserDataGuard(db, prefs);
    await db.db.insert('local_progress', {'lesson_id': 1, 'course_id': 1, 'completed_at': 1});
    expect(await guard.onLogin('A'), false); // première connexion
    expect(await guard.onLogin('A'), false); // même compte
    expect((await db.db.query('local_progress')).length, 1);
    expect(await guard.onLogin('B'), true); // autre compte
    expect((await db.db.query('local_progress')).length, 0);
  });

  test('rejected : conservé comme refusé et ne bloque pas la file', () async {
    await outbox.enqueue('lesson_completed', {'lesson_id': 1}, id: 'a');
    await outbox.enqueue('lesson_completed', {'lesson_id': 2}, id: 'b');
    final gw = _SeqGw([PushOutcome.rejected, PushOutcome.synced]);
    final sync = SyncService(outbox, gw);
    final rejected = <String>[];
    sync.onItemRejected = (i) => rejected.add(i.id);
    await sync.flush();
    expect(rejected, ['a']);
    expect(await outbox.pendingCount(), 0); // a refusé, b synchronisé
  });

  test('unavailable (chat) ne bloque pas les leçons derrière lui', () async {
    await outbox.enqueue('chat_message', {'body': 'x'}, id: 'c');
    await outbox.enqueue('lesson_completed', {'lesson_id': 5}, id: 'l');
    final gw = _SeqGw([PushOutcome.unavailable, PushOutcome.synced]);
    final sync = SyncService(outbox, gw);
    await sync.flush();
    final left = await outbox.pending();
    expect(left.map((i) => i.id), ['c']);
  });
}

class _SeqGw implements SyncGateway {
  _SeqGw(this.seq);
  final List<PushOutcome> seq;
  int i = 0;
  @override
  Future<PushOutcome> push(OutboxItem item) async => seq[i++];
}
