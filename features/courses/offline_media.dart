import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../core/widgets/net_image.dart' show kImageHeaders;
import 'models.dart';

/// Téléchargement des fichiers médias d'un cours pour le mode hors ligne.
///
/// - Images : stockées dans le cache disque par défaut (celui de CachedNetworkImage),
///   donc `NetImage` / `ImageViewerPage` les affichent sans réseau.
/// - Audio / PDF / vidéo / fichiers : stockés dans un cache dédié, sans expiration
///   (OfflineMediaCache), lisibles via [OfflineMedia.localFile].
class OfflineMediaCache {
  static const key = 'educadim_offline_media';
  static final CacheManager instance = CacheManager(
    Config(key, stalePeriod: const Duration(days: 3650), maxNrOfCacheObjects: 5000),
  );
}

class OfflineMedia {
  /// URLs de médias d'une leçon (toutes sections confondues).
  static List<({String url, String type})> urlsOfLesson(Lesson l) {
    final out = <({String url, String type})>[];
    for (final s in l.sections) {
      for (final c in s.contenus) {
        if (c.type == 'texte' || c.type == 'lien') continue;
        for (final e in [
          (c.imageUrl, 'image'), (c.audioUrl, 'audio'), (c.pdfUrl, 'pdf'), (c.videoUrl, 'video'),
        ]) {
          final u = e.$1;
          if (u != null && u.startsWith('http')) out.add((url: u, type: e.$2));
        }
      }
    }
    return out;
  }

  static List<String> urlsOfQuiz(QuizDetail q) {
    final out = <String>[];
    for (final qu in q.questions) {
      for (final u in [qu.image, qu.audio, qu.video]) {
        if (u != null && u.startsWith('http')) out.add(u);
      }
    }
    return out;
  }

  /// Télécharge [url] ; renvoie true si le fichier est (déjà) en cache.
  static Future<bool> prefetch(String url, String type) async {
    try {
      final mgr = type == 'image' ? DefaultCacheManager() : OfflineMediaCache.instance;
      final info = type == 'image'
          ? await mgr.downloadFile(url, authHeaders: kImageHeaders, force: true)
          : await mgr.downloadFile(url, force: true);
      // Vérifie que c'est bien un fichier (et pas une page HTML d'erreur / Cloudflare).
      final f = info.file;
      final len = await f.length();
      if (len < 50) {
        await mgr.removeFile(url);
        return false;
      }
      final head = await f.openRead(0, 16).first;
      final isHtml = head.isNotEmpty && (head[0] == 0x3C /* < */ || head[0] == 0x7B /* { */);
      if (isHtml) {
        await mgr.removeFile(url);
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> evict(String url) async {
    try {
      await DefaultCacheManager().removeFile(url);
      await OfflineMediaCache.instance.removeFile(url);
    } catch (_) {}
  }

  /// Chemin local d'un fichier déjà téléchargé (null s'il n'y est pas).
  static Future<String?> localFile(String url) async {
    try {
      final f = await OfflineMediaCache.instance.getFileFromCache(url) ??
          await DefaultCacheManager().getFileFromCache(url);
      return f?.file.path;
    } catch (_) {
      return null;
    }
  }
}
