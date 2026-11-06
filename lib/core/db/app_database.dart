import 'package:path/path.dart' as pth;
import 'package:sqflite/sqflite.dart';

/// Base SQLite locale.
/// - outbox : opérations à envoyer au serveur (jamais supprimées avant
///   confirmation de synchronisation).
/// - chat_messages : historique local du chat.
/// - downloads : contenus téléchargés pour le hors-ligne.
class AppDatabase {
  AppDatabase(this.db);
  final Database db;

  static const int version = 3;

  static Future<AppDatabase> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final file = path ?? pth.join(await f.getDatabasesPath(), 'educadim.db');
    final db = await f.openDatabase(
      file,
      options: OpenDatabaseOptions(
          version: version, onCreate: _create, onUpgrade: _upgrade),
    );
    return AppDatabase(db);
  }

  static Future<void> _upgrade(Database d, int from, int to) async {
    if (from < 2) await _createV2(d);
    if (from < 3) {
      await d.execute('ALTER TABLE chat_messages ADD COLUMN room_id INTEGER');
    }
  }

  static Future<void> _createV2(Database d) async {
    // Réponses API mises en cache (lecture hors ligne)
    await d.execute('''
      CREATE TABLE IF NOT EXISTS api_cache(
        key TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    // Progression enregistrée localement (en attente d'un endpoint serveur)
    await d.execute('''
      CREATE TABLE IF NOT EXISTS local_progress(
        lesson_id INTEGER PRIMARY KEY,
        course_id INTEGER NOT NULL,
        completed_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    // Cours dont le contenu texte est disponible hors ligne
    await d.execute('''
      CREATE TABLE IF NOT EXISTS offline_courses(
        course_id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        lessons INTEGER NOT NULL,
        skipped INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
  }

  static Future<void> _create(Database d, int v) async {
    await d.execute('''
      CREATE TABLE outbox(
        id TEXT PRIMARY KEY,           -- identifiant client stable (idempotence)
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,         -- JSON
        created_at INTEGER NOT NULL,   -- epoch ms
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        status TEXT NOT NULL DEFAULT 'pending',  -- pending | synced
        synced_at INTEGER
      )''');
    await d.execute('CREATE INDEX idx_outbox_status ON outbox(status, created_at)');
    await d.execute('''
      CREATE TABLE chat_messages(
        id TEXT PRIMARY KEY,
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        direction TEXT NOT NULL,       -- out | in
        state TEXT NOT NULL,           -- pending | sent | failed
        room_id INTEGER                -- salon serveur (null = ancien chat local)
      )''');
    await d.execute('''
      CREATE TABLE downloads(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        local_path TEXT NOT NULL,
        bytes INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await _createV2(d);
  }

  Future<void> close() => db.close();
}
