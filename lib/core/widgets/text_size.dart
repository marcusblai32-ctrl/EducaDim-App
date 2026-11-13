import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import '../i18n/text.dart';

/// Taille du texte de lecture (leçons, quiz) : boutons A− / A+ , mémorisée sur l'appareil.
class TextSizePref {
  static const _key = 'reading_text_scale';
  static const min = 0.85, max = 2.0, step = 0.15;
  static final ValueNotifier<double> scale = ValueNotifier(1.0);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      scale.value = (p.getDouble(_key) ?? 1.0).clamp(min, max);
    } catch (_) {}
  }

  static Future<void> change(double delta) async {
    scale.value = (scale.value + delta).clamp(min, max);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_key, scale.value);
    } catch (_) {}
  }
}

/// Applique l'échelle choisie à tout le texte de l'écran enfant.
class TextSizeScope extends StatefulWidget {
  const TextSizeScope({super.key, required this.child});
  final Widget child;
  @override
  State<TextSizeScope> createState() => _TextSizeScopeState();
}

class _TextSizeScopeState extends State<TextSizeScope> {
  @override
  void initState() {
    super.initState();
    TextSizePref.load();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: TextSizePref.scale,
        builder: (context, s, _) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * s)),
            child: widget.child,
          );
        },
      );
}

/// Les deux boutons « A » (petit / grand) pour la barre d'application.
List<Widget> textSizeActions() => [
      IconButton(
        tooltip: tr('Réduire le texte'),
        icon: const Text('A', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        onPressed: () => TextSizePref.change(-TextSizePref.step),
      ),
      IconButton(
        tooltip: tr('Agrandir le texte'),
        icon: const Text('A', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        onPressed: () => TextSizePref.change(TextSizePref.step),
      ),
    ];
