import 'dart:convert';
import 'package:flutter/material.dart' hide Text;
import 'package:webview_flutter/webview_flutter.dart';
import '../config/api_config.dart';
import '../i18n/text.dart';
import '../theme/colors.dart';

/// Lecteur audio INTÉGRÉ à l'application (même technique que la vidéo : lecteur HTML5 dans une WebView).
/// Il ne se charge qu'au toucher. Si le fichier ne se lit pas, un bouton « Ouvrir » reste disponible.
class AudioPlayerTile extends StatefulWidget {
  const AudioPlayerTile({super.key, required this.url, this.title, this.mime});
  final String url;
  final String? title;
  final String? mime;
  @override
  State<AudioPlayerTile> createState() => _AudioPlayerTileState();
}

class _AudioPlayerTileState extends State<AudioPlayerTile> {
  bool _active = false;
  WebViewController? _c;

  String get _html {
    final esc = const HtmlEscape(HtmlEscapeMode.attribute).convert(widget.url);
    final type = (widget.mime ?? '').isEmpty ? '' : ' type="${const HtmlEscape(HtmlEscapeMode.attribute).convert(widget.mime!)}"';
    const css = 'html,body{margin:0;height:100%;background:#fff;display:flex;align-items:center}'
        'audio{width:100%}';
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1"><style>$css</style></head>'
        '<body oncontextmenu="return false"><audio controls autoplay controlsList="nodownload noplaybackrate" '
        'preload="auto" playsinline><source src="$esc"$type></audio></body></html>';
  }

  void _start() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          if (!r.isMainFrame) return NavigationDecision.navigate;
          final ok = r.url.startsWith(ApiConfig.siteUrl) || r.url.startsWith('about:') || r.url.startsWith('data:');
          return ok ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
      ))
      ..loadHtmlString(_html, baseUrl: ApiConfig.siteUrl);
    setState(() {
      _c = c;
      _active = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.title ?? '').isNotEmpty ? widget.title! : tr('Audio');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.headphones, color: EdColors.blue),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          if (_active && _c != null)
            SizedBox(height: 64, child: WebViewWidget(controller: _c!))
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(tr('Écouter')),
              ),
            ),
        ]),
      ),
    );
  }
}
