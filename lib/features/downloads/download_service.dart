import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pth;
import 'package:path_provider/path_provider.dart';
import '../../core/db/app_database.dart';

class DownloadedItem {
  DownloadedItem(this.id, this.title, this.path, this.bytes, this.createdAt);
  final String id;
  final String title;
  final String path;
  final int bytes;
  final DateTime createdAt;
}

/// Téléchargement de ressources vers le stockage local.
/// Utilise un Dio distinct SANS jeton : les URL de ressources peuvent pointer
/// vers un stockage tiers et ne doivent pas recevoir le JWT.
class DownloadService extends ChangeNotifier {
  DownloadService(this._db, {Dio? dio, Future<Directory> Function()? dirProvider})
      : _dio = dio ?? Dio(),
        _dirProvider = dirProvider ?? getApplicationDocumentsDirectory;

  final AppDatabase _db;
  final Dio _dio;
  final Future<Directory> Function() _dirProvider;

  List<DownloadedItem> items = [];
  int get totalBytes => items.fold(0, (a, b) => a + b.bytes);

  Future<void> load() async {
    final rows = await _db.db.query('downloads', orderBy: 'created_at DESC');
    items = rows
        .map((r) => DownloadedItem(
              r['id'] as String,
              r['title'] as String,
              r['local_path'] as String,
              r['bytes'] as int,
              DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
            ))
        .toList();
    notifyListeners();
  }

  Future<void> download(String id, String title, String url) async {
    final dir = Directory(pth.join((await _dirProvider()).path, 'downloads'));
    await dir.create(recursive: true);
    final file = File(pth.join(dir.path, id));
    try {
      await _dio.download(url, file.path);
    } catch (_) {
      if (await file.exists()) await file.delete(); // pas de fichier partiel
      rethrow;
    }
    await _db.db.insert(
      'downloads',
      {
        'id': id,
        'title': title,
        'local_path': file.path,
        'bytes': await file.length(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
    await load();
  }

  Future<void> remove(String id) async {
    final rows =
        await _db.db.query('downloads', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      final f = File(rows.first['local_path'] as String);
      if (await f.exists()) await f.delete();
    }
    await _db.db.delete('downloads', where: 'id = ?', whereArgs: [id]);
    await load();
  }
}
