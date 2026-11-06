import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/app_database.dart';
import '../../core/db/outbox_repository.dart';
import '../../core/sync/sync_service.dart';

class ChatMessage {
  ChatMessage(this.id, this.body, this.createdAt, this.direction, this.state);
  final String id;
  final String body;
  final DateTime createdAt;
  final String direction; // out | in
  final String state; // pending | sent
  bool get isMine => direction == 'out';
  bool get isPending => state == 'pending';
}

/// Historique local + file d'attente. Un message n'est "envoyé" que lorsque
/// le serveur a confirmé ; tant que l'endpoint de chat n'est pas confirmé il
/// reste "en attente" (jamais de faux envoi).
class ChatController extends ChangeNotifier {
  ChatController(this._db, this._outbox, this._sync) {
    _sync.onItemSynced = _onSynced;
  }
  final AppDatabase _db;
  final OutboxRepository _outbox;
  final SyncService _sync;

  List<ChatMessage> messages = [];

  Future<void> load() async {
    final rows = await _db.db.query('chat_messages', orderBy: 'created_at ASC');
    messages = rows
        .map((r) => ChatMessage(
              r['id'] as String,
              r['body'] as String,
              DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
              r['direction'] as String,
              r['state'] as String,
            ))
        .toList();
    notifyListeners();
  }

  Future<void> send(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final id = const Uuid().v4();
    final now = DateTime.now();
    await _db.db.insert('chat_messages', {
      'id': id,
      'body': body,
      'created_at': now.millisecondsSinceEpoch,
      'direction': 'out',
      'state': 'pending',
    });
    await _outbox.enqueue(
      'chat_message',
      {'client_id': id, 'body': body, 'created_at': now.toUtc().toIso8601String()},
      id: id,
    );
    await load();
    await _sync.refreshCount();
    unawaited(_sync.flush());
  }

  Future<void> _onSynced(OutboxItem item) async {
    if (item.kind != 'chat_message') return;
    await _db.db.update('chat_messages', {'state': 'sent'},
        where: 'id = ?', whereArgs: [item.id]);
    await load();
  }
}
