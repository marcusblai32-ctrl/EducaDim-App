import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/db/app_database.dart';
import '../../core/security/secure_files.dart';

class DownloadedItem {
  DownloadedItem(this.id, this.title, this.bytes, this.createdAt, this.courseId);
  final String id;
  final String title;
  final int bytes;
  final DateTime createdAt;
  final int? courseId;
}

/// Téléchargement de documents PDF, CHIFFRÉS sur le téléphone (voir SecureFiles).
/// Utilise un Dio distinct SANS jeton : les URL de ressources peuvent pointer vers un stockage tiers.
/// Les fichiers ne sont lisibles que dans EducaDim (visionneuse intégrée) ; ils ne passent jamais par une autre application.
class DownloadService extends ChangeNotifier {
  DownloadService(this._db, {Dio? dio, SecureFiles? files})
      : _dio = dio ?? Dio(),
        _files = files ?? SecureFiles();

  final AppDatabase _db;
  final Dio _dio;
  final SecureFiles _files;

  List<DownloadedItem> items = [];
  int get totalBytes => items.fold(0, (a, b) => a + b.bytes);

  Future<void> load() async {
    await _removeLegacy();
    final rows = await _db.db.query('downloads', orderBy: 'created_at DESC');
    items = rows
        .map((r) => DownloadedItem(
              r['id'] as String,
              r['title'] as String,
              r['bytes'] as int,
              DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
              (r['course_id'] as num?)?.toInt(),
            ))
        .toList();
    notifyListeners();
  }

  /// Anciennes versions : fichiers en clair dans « Documents ». On les supprime (à retélécharger, chiffrés).
  Future<void> _removeLegacy() async {
    try {
      final rows = await _db.db.query('downloads', where: 'local_path NOT LIKE ?', whereArgs: ['secure:%']);
      if (rows.isEmpty) return;
      for (final r in rows) {
        final f = File(r['local_path'] as String);
        if (await f.exists()) await f.delete();
      }
      await _db.db.delete('downloads', where: 'local_path NOT LIKE ?', whereArgs: ['secure:%']);
      final old = Directory('${(await getApplicationDocumentsDirectory()).path}/downloads');
      if (await old.exists()) await old.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> download(String id, String title, String url, {int? courseId, int? accessUntil}) async {
    final res = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 3)),
    );
    final data = Uint8List.fromList(res.data ?? const []);
    if (data.isEmpty) throw StateError('empty');
    if (data.length > SecureFiles.maxBytes) throw StateError('too_big');
    final size = await _files.write(id, data);
    await _db.db.insert(
      'downloads',
      {
        'id': id,
        'title': title,
        'local_path': 'secure:$id',
        'bytes': size,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'course_id': courseId,
        'access_until': accessUntil,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await load();
  }

  bool has(String id) => items.any((i) => i.id == id);

  /// Contenu déchiffré en mémoire pour la visionneuse (null si absent ou modifié).
  Future<Uint8List?> readBytes(String id) => _files.read(id);

  Future<void> remove(String id) async {
    await _files.delete(id);
    await _db.db.delete('downloads', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  Future<void> removeByCourse(int courseId) async {
    final rows = await _db.db.query('downloads', where: 'course_id = ?', whereArgs: [courseId]);
    for (final r in rows) {
      await _files.delete(r['id'] as String);
    }
    await _db.db.delete('downloads', where: 'course_id = ?', whereArgs: [courseId]);
    await load();
  }

  /// Changement de compte ou déconnexion : tout est effacé.
  Future<void> purgeAll() async {
    await _files.deleteAll();
    await _db.db.delete('downloads');
    await load();
  }
}
