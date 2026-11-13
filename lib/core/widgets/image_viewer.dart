import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';
import '../i18n/text.dart';
import 'net_image.dart';

/// Image de leçon / de quiz : un appui l'ouvre en plein écran avec zoom.
class ZoomableNetImage extends StatelessWidget {
  const ZoomableNetImage(this.url, {super.key, this.title, this.borderRadius = 12});
  final String? url;
  final String? title;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final u = url;
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: NetImage(u, aspectRatio: null, fit: BoxFit.fitWidth),
      ),
      if (u != null && u.isNotEmpty) ...[
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(borderRadius),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => ImageViewerPage(u, title: title),
              )),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Plein écran : pincer pour zoomer, glisser pour déplacer, double appui pour zoom ×3.
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage(this.url, {super.key, this.title});
  final String url;
  final String? title;
  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> with SingleTickerProviderStateMixin {
  final _ctrl = TransformationController();
  TapDownDetails? _tap;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _doubleTap() {
    if (_ctrl.value.getMaxScaleOnAxis() > 1.05) {
      _ctrl.value = Matrix4.identity();
    } else {
      final p = _tap?.localPosition ?? Offset.zero;
      _ctrl.value = Matrix4.identity()
        ..translate(-p.dx * 2, -p.dy * 2)
        ..scale(3.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr('Ouvrir dans le navigateur'),
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
          ),
          IconButton(
            tooltip: tr('Taille d’origine'),
            icon: const Icon(Icons.fit_screen_rounded),
            onPressed: () => _ctrl.value = Matrix4.identity(),
          ),
        ],
      ),
      body: GestureDetector(
        onDoubleTapDown: (d) => _tap = d,
        onDoubleTap: _doubleTap,
        child: InteractiveViewer(
          transformationController: _ctrl,
          minScale: 1,
          maxScale: 8,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.url,
              httpHeaders: kImageHeaders,
              fit: BoxFit.contain,
              width: double.infinity,
              placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Image indisponible hors ligne.'), style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
