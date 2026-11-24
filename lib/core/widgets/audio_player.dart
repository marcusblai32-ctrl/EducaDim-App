import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:webview_flutter/webview_flutter.dart';
import '../config/api_config.dart';
import '../i18n/text.dart';
import '../theme/colors.dart';

/// Lecteur audio INTÉGRÉ à l'application.
/// Le fichier est téléchargé EN MÉMOIRE par l'application (Dio), puis lu par un lecteur HTML5 : le lecteur ne dépend plus
/// du réseau de la WebView (types MIME, en-têtes, protection anti-hotlink de Cloudflare…), et l'adresse du fichier n'est
/// jamais exposée. Rien n'est écrit sur le téléphone, aucun bouton « ouvrir / télécharger ».
class AudioPlayerTile extends StatefulWidget {
  const AudioPlayerTile({super.key, required this.url, this.title, this.mime});
  final String url;
  final String? title;
  final String? mime;
  @override
  State<AudioPlayerTile> createState() => _AudioPlayerTileState();
}

class _AudioPlayerTileState extends State<AudioPlayerTile> {
  static const _maxBytes = 25 * 1024 * 1024;
  bool _loading = false;
  String? _error;
  WebViewController? _c;

  static const _mimes = {
    'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'm4a': 'audio/mp4', 'aac': 'audio/aac', 'ogg': 'audio/ogg',
    'oga': 'audio/ogg', 'opus': 'audio/ogg', 'flac': 'audio/flac', 'weba': 'audio/webm',
  };

  String get _mime {
    if ((widget.mime ?? '').isNotEmpty) return widget.mime!;
    final path = Uri.tryParse(widget.url)?.path.toLowerCase() ?? '';
    final ext = path.contains('.') ? path.substring(path.lastIndexOf('.') + 1) : '';
    return _mimes[ext] ?? 'audio/mpeg';
  }

  String _html(String src) {
    const css = 'html,body{margin:0;height:100%;background:#fff;display:flex;flex-direction:column;justify-content:center}audio{width:100%}'
        '.b{display:flex;gap:6px;justify-content:center;margin-top:4px}.b button{border:0;border-radius:14px;padding:5px 10px;background:#e8eefc;font-size:12px}';
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1"><style>$css</style></head>'
        '<body oncontextmenu="return false"><audio controls controlsList="nodownload" preload="auto" id="a" '
        'playsinline src="$src" onerror="Err.postMessage(String(this.error?this.error.code:0))"></audio>'
        '<div class="b"><button onclick="a.currentTime=Math.max(0,a.currentTime-10)">⏪ 10</button>'
        '<button onclick="a.currentTime+=10">10 ⏩</button>'
        '<button id="sp" onclick="var r=[1,1.25,1.5,2,0.75];window.i=((window.i||0)+1)%5;a.playbackRate=r[window.i];this.textContent=r[window.i]+\'x\'">1x</button>'
        '<button id="lp" style="opacity:.5" onclick="a.loop=!a.loop;this.style.opacity=a.loop?1:.5">🔁</button></div></body></html>';
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Dio().get<List<int>>(
        widget.url,
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)),
      );
      final data = res.data;
      if (data == null || data.isEmpty) throw Exception('empty');
      if (data.length > _maxBytes) throw Exception('big');
      final src = 'data:$_mime;base64,${base64Encode(Uint8List.fromList(data))}';
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel('Err', onMessageReceived: (m) {
          if (mounted) setState(() => _error = tr('Ce fichier audio n’est pas lisible (format non supporté). Utilise MP3.'));
        })
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (r) {
            final ok = r.url.startsWith(ApiConfig.siteUrl) || r.url.startsWith('about:') || r.url.startsWith('data:');
            return ok ? NavigationDecision.navigate : NavigationDecision.prevent;
          },
        ))
        ..loadHtmlString(_html(src), baseUrl: ApiConfig.siteUrl);
      if (!mounted) return;
      setState(() {
        _c = c;
        _loading = false;
      });
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (mounted) {
        setState(() {
          _loading = false;
          _error = code != null
              ? tr('Fichier inaccessible (erreur {c}). Vérifie que le fichier est bien envoyé et public.', {'c': code})
              : tr('Impossible de charger l’audio. Vérifie ta connexion.');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = tr('Impossible de lire cet audio (fichier trop lourd ou vide). Utilise un MP3 de moins de 25 Mo.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.title ?? '').isNotEmpty ? widget.title! : tr('Audio');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.headphones, color: EdColors.blue),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          if (_c != null && _error == null)
            SizedBox(height: 104, child: WebViewWidget(controller: _c!))
          else if (_loading)
            const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
          else ...[
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_error!)),
            FilledButton.icon(
              onPressed: _start,
              icon: Icon(_error == null ? Icons.play_arrow_rounded : Icons.refresh),
              label: Text(_error == null ? tr('Écouter') : tr('Réessayer')),
            ),
          ],
        ]),
      ),
    );
  }
}
