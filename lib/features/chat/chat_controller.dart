import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/i18n/lang.dart';
import 'package:uuid/uuid.dart';
import '../../core/alerts/alert_service.dart';
import '../../core/db/app_database.dart';
import '../../core/db/cache_store.dart';
import '../../core/db/outbox_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/sync/sync_service.dart';

class ChatRoomSummary {
  ChatRoomSummary(this.id, this.titre, this.type, this.courseId, this.lastText,
      this.lastUser, this.lastAt, {this.lastMine = false, this.onlineCount = 0});
  final int id;
  final String titre, type;
  final int? courseId;
  final String? lastText, lastUser;
  final DateTime? lastAt;
  final bool lastMine;
  final int onlineCount; // autres participants en ligne (point vert)

  factory ChatRoomSummary.fromJson(dynamic j) {
    final m = j is Map ? j : const {};
    final last = m['last_message'] is Map ? m['last_message'] as Map : null;
    return ChatRoomSummary(
      m['id'] is int ? m['id'] as int : 0,
      m['titre'] is String ? m['titre'] as String : 'Salon',
      m['type'] is String ? m['type'] as String : 'group',
      m['course_id'] is int ? m['course_id'] as int : null,
      last?['contenu'] as String?,
      last?['user_name'] as String?,
      DateTime.tryParse((last?['created_at'] as String?) ?? '')?.toLocal(),
      lastMine: last?['mine'] == true,
      onlineCount: m['online_count'] is int ? m['online_count'] as int : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titre': titre,
        'type': type,
        'course_id': courseId,
        'online_count': onlineCount,
        'last_message': lastText == null
            ? null
            : {
                'contenu': lastText,
                'user_name': lastUser,
                'mine': lastMine,
                'created_at': lastAt?.toUtc().toIso8601String(),
              },
      };
}

class ChatMessage {
  ChatMessage({
    required this.key,
    this.serverId,
    required this.userName,
    required this.body,
    required this.createdAt,
    required this.mine,
    required this.state,
  });
  final String key; // identifiant stable (serveur: "s<id>", local: uuid)
  final int? serverId;
  final String userName, body, state; // state : sent | pending | failed
  final DateTime createdAt;
  final bool mine;
  bool get isPending => state == 'pending';
  bool get isFailed => state == 'failed';

  factory ChatMessage.fromServer(dynamic j) {
    final m = j is Map ? j : const {};
    final id = m['id'] is int ? m['id'] as int : 0;
    return ChatMessage(
      key: 's$id',
      serverId: id,
      userName: m['user_name'] is String ? m['user_name'] as String : '',
      body: m['contenu'] is String ? m['contenu'] as String : '',
      createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal() ??
          DateTime.now(),
      mine: m['mine'] == true,
      state: 'sent',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': serverId,
        'user_name': userName,
        'contenu': body,
        'mine': mine,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

/// Salons et messages réels (API chat). Les messages écrits hors ligne sont
/// gardés en SQLite (`chat_messages`, état pending) et envoyés via la file
/// d'attente avec un `client_id` stable ; ils ne sont « envoyés » qu'après
/// confirmation du serveur, puis remplacés par le message serveur.
class ChatController extends ChangeNotifier {
  ChatController(this._api, this._db, this._cache, this._outbox, this._sync) {
    _sync.onItemSynced = _onSynced;
  }
  final ApiClient _api;
  final AppDatabase _db;
  final CacheStore _cache;
  final OutboxRepository _outbox;
  final SyncService _sync;

  // ---- salons ----
  List<ChatRoomSummary> rooms = [];
  bool roomsLoading = false;
  bool roomsFromCache = false;
  String? roomsError;

  // ---- messages ----
  final Map<int, List<ChatMessage>> _server = {};
  final Map<int, List<ChatMessage>> _local = {};
  final Map<int, bool> roomOffline = {};
  final Map<int, String?> roomError = {};

  int? activeRoom;
  Timer? _poll;
  final Map<int, DateTime> _seenLast = {};
  bool _roomsBaseline = false;

  int get totalPending => _local.values.fold(0, (a, l) => a + l.length);

  void reset() {
    rooms = [];
    _server.clear();
    _local.clear();
    roomOffline.clear();
    roomError.clear();
    roomsError = null;
    _seenLast.clear();
    _roomsBaseline = false;
    notifyListeners();
  }

  void closeRoom(int id) {
    if (activeRoom == id) activeRoom = null;
  }

  /// Vérifie les salons toutes les 45 s (application ouverte) : son pour un nouveau message.
  void startPolling(bool Function() loggedIn) {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
      if (loggedIn()) loadRooms(silent: true);
    });
  }

  void _detectNew() {
    for (final r in rooms) {
      final at = r.lastAt;
      if (at == null) continue;
      final prev = _seenLast[r.id];
      final isNew = prev == null || at.isAfter(prev);
      if (_roomsBaseline && isNew && !r.lastMine && r.id != activeRoom) {
        AlertService.instance.notify(tr('Nouveau message'), '${r.titre} — ${r.lastUser ?? ''}: ${r.lastText ?? ''}');
      }
      if (isNew) _seenLast[r.id] = at;
    }
    _roomsBaseline = true;
  }

  Future<void> loadRooms({bool silent = false}) async {
    if (!silent) {
      roomsLoading = true;
      roomsError = null;
      notifyListeners();
    }
    try {
      final res = await _api.dio.get('chat/rooms/');
      final raw = res.data is Map && res.data['rooms'] is List ? res.data['rooms'] as List : [];
      rooms = raw.map(ChatRoomSummary.fromJson).toList();
      roomsFromCache = false;
      _detectNew();
      await _cache.put('chat:rooms', {'rooms': rooms.map((r) => r.toJson()).toList()});
    } on DioException catch (e) {
      final ex = mapDio(e);
      if (rooms.isEmpty) {
        final c = await _cache.get('chat:rooms');
        if (c is Map && c['rooms'] is List) {
          rooms = (c['rooms'] as List).map(ChatRoomSummary.fromJson).toList();
          roomsFromCache = true;
        }
      } else {
        roomsFromCache = true;
      }
      if (rooms.isEmpty) {
        roomsError = ex.statusCode == 404
            ? tr('Cette fonctionnalité n’est pas disponible pour le moment.')
            : ex.message;
      }
    } finally {
      roomsLoading = false;
      notifyListeners();
    }
  }

  /// Ouvre (ou crée) le salon de groupe d'un cours auquel l'utilisateur est inscrit.
  Future<int> openCourseRoom(int courseId) async {
    try {
      final res = await _api.dio.post('chat/rooms/group/$courseId/');
      return res.data['id'] as int;
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  List<ChatMessage> messages(int roomId) {
    final all = <ChatMessage>[...?_server[roomId], ...?_local[roomId]];
    all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return all;
  }

  Future<void> openRoom(int roomId) async {
    activeRoom = roomId;
    await _loadLocal(roomId);
    if (_server[roomId] == null) {
      final c = await _cache.get('chat:room:$roomId');
      if (c is List) {
        _server[roomId] = c.map(ChatMessage.fromServer).toList();
        roomOffline[roomId] = true;
      }
    }
    notifyListeners();
    await fetch(roomId);
  }

  Future<void> _loadLocal(int roomId) async {
    final rows = await _db.db.query('chat_messages',
        where: 'room_id = ?', whereArgs: [roomId], orderBy: 'created_at ASC');
    _local[roomId] = rows
        .map((r) => ChatMessage(
              key: r['id'] as String,
              userName: 'Moi',
              body: r['body'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
              mine: true,
              state: r['state'] as String,
            ))
        .toList();
  }

  /// Récupère les nouveaux messages (incrémental avec `after`).
  Future<void> fetch(int roomId) async {
    final have = _server[roomId] ?? [];
    final lastId = have.isEmpty ? null : have.last.serverId;
    try {
      final res = await _api.dio.get('chat/rooms/$roomId/messages/',
          queryParameters: lastId == null ? null : {'after': lastId});
      final raw = res.data is Map && res.data['messages'] is List ? res.data['messages'] as List : [];
      final incoming = raw.map(ChatMessage.fromServer).toList();
      final known = {for (final m in have) m.serverId};
      final fresh = incoming.where((m) => !known.contains(m.serverId) && !m.mine).toList();
      if (have.isNotEmpty && fresh.isNotEmpty) {
        AlertService.instance.notify(tr('Nouveau message'), '${fresh.last.userName}: ${fresh.last.body}');
      }
      final byId = {for (final m in have) m.serverId: m};
      for (final m in incoming) {
        byId[m.serverId] = m;
      }
      final merged = byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _server[roomId] = merged.length > 200 ? merged.sublist(merged.length - 200) : merged;
      roomOffline[roomId] = false;
      roomError[roomId] = null;
      await _cache.put('chat:room:$roomId', _server[roomId]!.map((m) => m.toJson()).toList());
    } on DioException catch (e) {
      final ex = mapDio(e);
      roomOffline[roomId] = ex.isOffline;
      roomError[roomId] = ex.isOffline ? null : ex.message;
    }
    notifyListeners();
  }

  Future<void> send(int roomId, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final id = const Uuid().v4();
    await _db.db.insert('chat_messages', {
      'id': id,
      'body': body,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'direction': 'out',
      'state': 'pending',
      'room_id': roomId,
    });
    await _outbox.enqueue(
      'chat_message',
      {'room_id': roomId, 'client_id': id, 'contenu': body},
      id: id,
    );
    await _loadLocal(roomId);
    notifyListeners();
    await _sync.refreshCount();
    unawaited(_sync.flush());
  }

  Future<void> _onSynced(OutboxItem item) async {
    if (item.kind != 'chat_message') return;
    final rid = item.payload['room_id'];
    // Le message existe maintenant côté serveur : on retire la copie locale.
    await _db.db.delete('chat_messages', where: 'id = ?', whereArgs: [item.id]);
    if (rid is int) {
      await _loadLocal(rid);
      await fetch(rid);
    }
  }

  Future<void> handleRejected(String outboxId) async {
    await _db.db.update('chat_messages', {'state': 'failed'},
        where: 'id = ?', whereArgs: [outboxId]);
    for (final k in _local.keys.toList()) {
      await _loadLocal(k);
    }
    notifyListeners();
  }
}
