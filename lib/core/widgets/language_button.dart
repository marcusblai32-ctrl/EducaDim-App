import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';

/// Bouton de langue (FR / KR) : globe + code de la langue courante.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final lang = Lang.instance;
    final fg = onDark ? Colors.white : Theme.of(context).colorScheme.primary;
    final bg = onDark ? Colors.white.withValues(alpha: 0.18) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.10);
    return PopupMenuButton<String>(popUpAnimationStyle: AnimationStyle.noAnimation, 
      tooltip: tr('Langue'),
      onSelected: lang.set,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: 'fr', checked: lang.code == 'fr', child: const Text('Français')),
        CheckedPopupMenuItem(value: 'ht', checked: lang.code == 'ht', child: const Text('Kreyòl')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.language_rounded, size: 18, color: fg),
          const SizedBox(width: 5),
          Text(lang.code == 'ht' ? 'KR' : 'FR',
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
      ),
    );
  }
}
