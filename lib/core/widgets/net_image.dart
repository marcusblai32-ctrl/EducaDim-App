import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// En-têtes « navigateur » : certains CDN (Cloudflare/R2 avec protection anti-bots
/// ou anti-hotlink) refusent l'agent par défaut de Dart et renvoient 403.
const kImageHeaders = {
  'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
};

/// Image réseau adaptée à son conteneur :
///  - [aspectRatio] fixé (ex. 16/9) + `BoxFit.cover` : remplit toute la largeur du card ;
///  - [aspectRatio] null : largeur pleine, hauteur naturelle (images de leçon) ;
///  - cache disque (économise les données mobiles, fonctionne hors ligne pour les images déjà vues) ;
///  - placeholder pendant le chargement ; en cas d'échec : visuel de marque, et un appui
///    affiche la cause (utile pour diagnostiquer un 403/404).
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.aspectRatio = 16 / 9, this.fit = BoxFit.cover});
  final String? url;
  final double? aspectRatio;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final u = url;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final width = MediaQuery.of(context).size.width;
    Widget child;
    if (u == null || u.isEmpty) {
      child = const _Fallback();
    } else {
      child = CachedNetworkImage(
        imageUrl: u,
        httpHeaders: kImageHeaders,
        fit: fit,
        width: double.infinity,
        memCacheWidth: (width * dpr).round().clamp(300, 1400),
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => Container(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
        errorWidget: (ctx, failedUrl, error) => _Fallback(url: failedUrl, error: error),
      );
    }
    return aspectRatio == null ? child : AspectRatio(aspectRatio: aspectRatio!, child: child);
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({this.url, this.error});
  final String? url;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: error == null
          ? null
          : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              duration: const Duration(seconds: 6),
              content: Text('Image indisponible.\n${error.toString().split('\n').first}\n$url'))),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [EdColors.navy, EdColors.blue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Opacity(
            opacity: 0.35,
            child: Image.asset('assets/logo.png', height: 52),
          ),
        ),
      ),
    );
  }
}
