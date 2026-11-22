import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../features/courses/offline_media.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config/api_config.dart';
import '../i18n/text.dart';
import '../theme/colors.dart';

enum VideoKind { youtube, vimeo, drive, stream, file }

class VideoSource {
  VideoSource(this.kind, this.src);
  final VideoKind kind;
  final String src;

  static final _yt = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Même logique que le site (mobile_api/video.py) : YouTube, Vimeo, Google Drive, fichier direct.
  static VideoSource? parse(String? url) {
    final raw = (url ?? '').trim();
    final u = Uri.tryParse(raw);
    if (raw.isEmpty || u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) return null;
    var host = u.host.toLowerCase();
    for (final p in ['www.', 'm.']) {
      if (host.startsWith(p)) host = host.substring(p.length);
    }
    final path = u.pathSegments.where((e) => e.isNotEmpty).toList();

    String? vid;
    if (host == 'youtu.be' && path.isNotEmpty) {
      vid = path[0];
    } else if (host == 'youtube.com' || host == 'youtube-nocookie.com' || host == 'music.youtube.com') {
      if (path.isNotEmpty && path[0] == 'watch') {
        vid = u.queryParameters['v'];
      } else if (path.length >= 2 && const ['embed', 'shorts', 'live', 'v'].contains(path[0])) {
        vid = path[1];
      }
    }
    if (vid != null && _yt.hasMatch(vid)) {
      return VideoSource(VideoKind.youtube,
          'https://www.youtube-nocookie.com/embed/$vid?rel=0&modestbranding=1&playsinline=1&iv_load_policy=3');
    }

    if (host == 'vimeo.com' || host == 'player.vimeo.com') {
      final i = path.indexWhere((p) => RegExp(r'^\d+$').hasMatch(p));
      if (i >= 0) {
        var h = u.queryParameters['h'];
        if (h == null && i + 1 < path.length && RegExp(r'^[0-9a-f]{6,}$').hasMatch(path[i + 1])) h = path[i + 1];
        var src = 'https://player.vimeo.com/video/${path[i]}?dnt=1&title=0&byline=0&portrait=0';
        if (h != null && RegExp(r'^[0-9a-f]+$').hasMatch(h)) src += '&h=$h';
        return VideoSource(VideoKind.vimeo, src);
      }
    }

    if (host == 'drive.google.com' && path.length >= 3 && path[0] == 'file' && path[1] == 'd') {
      return VideoSource(VideoKind.drive, 'https://drive.google.com/file/d/${path[2]}/preview');
    }
    // Cloudflare Stream : intégrer le lecteur officiel (la page /watch n'est pas un fichier vidéo).
    if (host.endsWith('cloudflarestream.com') || host == 'videodelivery.net' || host == 'iframe.videodelivery.net') {
      final idRe = RegExp(r'^(?:[0-9a-f]{32}|eyJ[A-Za-z0-9_.-]{20,})$');
      final id = path.firstWhere((p) => idRe.hasMatch(p), orElse: () => '');
      if (id.isNotEmpty) {
        final src = host.endsWith('cloudflarestream.com')
            ? 'https://${u.host}/$id/iframe'
            : 'https://iframe.videodelivery.net/$id';
        return VideoSource(VideoKind.stream, src);
      }
    }
    return VideoSource(VideoKind.file, raw);
  }

  String get html {
    const css = 'html,body{margin:0;height:100%;background:#000;overflow:hidden}'
        'iframe,video{position:absolute;top:0;left:0;width:100%;height:100%;border:0;background:#000}';
    final esc = const HtmlEscape(HtmlEscapeMode.attribute).convert(src);
    final body = kind == VideoKind.file
        // Lecteur HTML5 sans téléchargement, sans menu contextuel, sans image dans l'image
        ? '<video src="$esc" controls controlsList="nodownload noremoteplayback" disablePictureInPicture '
            'playsinline preload="metadata" oncontextmenu="return false"></video>'
        : '<iframe src="$esc" allowfullscreen referrerpolicy="strict-origin-when-cross-origin" '
            'allow="autoplay; encrypted-media; picture-in-picture; fullscreen"></iframe>';
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1"><style>$css</style></head>'
        '<body oncontextmenu="return false">$body</body></html>';
  }
}

/// Vidéo intégrée et contrôlée : pas de bouton de téléchargement, navigation verrouillée
/// (aucune sortie vers YouTube/Vimeo). Le lecteur ne se charge qu'au toucher (économie de données).
class ControlledVideo extends StatefulWidget {
  const ControlledVideo({super.key, required this.url, this.title});
  final String url;
  final String? title;
  @override
  State<ControlledVideo> createState() => _ControlledVideoState();
}

class _ControlledVideoState extends State<ControlledVideo> {
  bool _active = false;

  Future<void> _fullscreen(VideoSource s) async {
    setState(() => _active = false); // un seul lecteur à la fois
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _FullscreenVideo(s)));
  }

  @override
  Widget build(BuildContext context) {
    final source = VideoSource.parse(widget.url);
    if (source == null) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Vidéo indisponible.'));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _active
            ? Stack(children: [
                Positioned.fill(child: _VideoFrame(source)),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    tooltip: tr('Plein écran'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.fullscreen_rounded),
                    onPressed: () => _fullscreen(source),
                  ),
                ),
              ])
            : InkWell(
                // Windows : pas de WebView intégrée → la vidéo s'ouvre dans le navigateur du système.
                onTap: Theme.of(context).platform == TargetPlatform.windows
                    ? () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication)
                    : () => setState(() => _active = true),
                child: Container(
                  decoration: const BoxDecoration(gradient: EdColors.hero),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, size: 40, color: EdColors.blue),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        (widget.title ?? '').isNotEmpty ? widget.title! : tr('Lire la vidéo'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                ),
              ),
      ),
    );
  }
}

class _VideoFrame extends StatefulWidget {
  const _VideoFrame(this.source);
  final VideoSource source;
  @override
  State<_VideoFrame> createState() => _VideoFrameState();
}

class _VideoFrameState extends State<_VideoFrame> {
  late final WebViewController _c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.black)
    ..setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (r) {
        // Cadre principal : uniquement notre page. Les sous-cadres (le lecteur) restent libres.
        if (!r.isMainFrame) return NavigationDecision.navigate;
        final ok = r.url.startsWith(ApiConfig.siteUrl) ||
            r.url.startsWith('about:') ||
            r.url.startsWith('data:') ||
            r.url.startsWith('file:');
        return ok ? NavigationDecision.navigate : NavigationDecision.prevent;
      },
    ));

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Hors ligne : si la vidéo (fichier direct) a été téléchargée avec le cours, on la lit depuis le téléphone.
  Future<void> _load() async {
    final s = widget.source;
    if (s.kind == VideoKind.file) {
      try {
        final local = await OfflineMedia.localFile(s.src);
        if (local != null && await File(local).exists()) {
          final dir = await getTemporaryDirectory();
          final page = File('${dir.path}/educadim_offline_player.html');
          final esc = const HtmlEscape(HtmlEscapeMode.attribute).convert(Uri.file(local).toString());
          await page.writeAsString('<!doctype html><html><head><meta charset="utf-8">'
              '<meta name="viewport" content="width=device-width,initial-scale=1">'
              '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}'
              'video{position:absolute;top:0;left:0;width:100%;height:100%;background:#000}</style></head>'
              '<body oncontextmenu="return false"><video src="$esc" controls controlsList="nodownload noremoteplayback" '
              'disablePictureInPicture playsinline preload="metadata"></video></body></html>');
          await _c.loadFile(page.path);
          return;
        }
      } catch (_) {
        // on retombe sur la lecture en ligne
      }
    }
    await _c.loadHtmlString(s.html, baseUrl: ApiConfig.siteUrl);
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _c);
}

class _FullscreenVideo extends StatelessWidget {
  const _FullscreenVideo(this.source);
  final VideoSource source;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: tr('Fermer'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(child: AspectRatio(aspectRatio: 16 / 9, child: _VideoFrame(source))),
      );
}
