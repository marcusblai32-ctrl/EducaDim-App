import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'app_database.dart';

class OutboxItem {
  OutboxItem({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    required this.attempts,
  });
  final String id;
  final String kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
}

class OutboxRepository {
  OutboxRepository(this._d);
  final AppDatabase _d;

  /// Ajoute une opération. Un `id` déjà présent est ignoré : pas de doublon.
  Future<String> enqueue(String kind, Map<String, dynamic> payload,
      {String? id}) async {
    final key = id ?? const Uuid().v4();
    await _d.db.insert(
      'outbox',
      {
        'id': key,
        'kind': kind,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return key;
  }

  Future<List<OutboxItem>> pending({int limit = 50}) async {
    final rows = await _d.db.query('outbox',
        where: "status = 'pending'", orderBy: 'created_at ASC', limit: limit);
    return rows
        .map((r) => OutboxItem(
              id: r['id'] as String,
              kind: r['kind'] as String,
              payload: jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
              attempts: r['attempts'] as int,
            ))
        .toList();
  }

  Future<int> pendingCount() async {
    final r = await _d.db
        .rawQuery("SELECT COUNT(*) c FROM outbox WHERE status = 'pending'");
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Marque comme synchronisé (la ligne est conservée, purge différée).
  Future<void> markSynced(String id) => _d.db.update(
        'outbox',
        {
          'status': 'synced',
          'synced_at': DateTime.now().millisecondsSinceEpoch,
          'last_error': null,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Refus définitif du serveur : conservé pour audit, ne bloque plus la file.
  Future<void> markRejected(String id, String reason) => _d.db.update(
        'outbox',
        {'status': 'rejected', 'last_error': reason},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> markFailed(String id, String error) => _d.db.rawUpdate(
        'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?',
        [error, id],
      );

  /// Supprime uniquement les lignes déjà confirmées synchronisées.
  Future<int> purgeSynced({Duration olderThan = const Duration(days: 7)}) {
    final limit = DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    return _d.db.delete('outbox',
        where: "status = 'synced' AND synced_at < ?", whereArgs: [limit]);
  }
}
