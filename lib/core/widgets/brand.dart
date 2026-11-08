import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import '../theme/colors.dart';

/// Nom de marque : « Educa » en bleu, « Dim » en rouge (comme le logo).
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        );
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Educa', style: style?.copyWith(color: dark ? EdColors.darkPrimary : EdColors.blue)),
        TextSpan(text: 'Dim', style: style?.copyWith(color: dark ? EdColors.darkRed : EdColors.red)),
      ]),
    );
  }
}
