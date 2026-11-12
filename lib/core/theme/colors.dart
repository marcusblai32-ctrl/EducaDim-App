import 'package:flutter/material.dart';

/// Palette issue du logo EducaDim : bleu royal et rouge.
class EdColors {
  // Marque
  static const blue = Color(0xFF0A12E8);
  static const blueDeep = Color(0xFF060C9C);
  static const red = Color(0xFFD22028);

  // Neutres (clair)
  static const bg = Color(0xFFF4F6FC);
  static const ink = Color(0xFF10143A);
  static const line = Color(0xFFE3E7F3);

  // Anciennes appellations conservées (utilisées par l'ensemble des écrans)
  static const navy = Color(0xFF0B1033);
  static const navyLight = Color(0xFF1B2470);
  static const turquoise = Color(0xFF8FA0FF); // bleu clair d'accentuation

  // États
  static const good = Color(0xFF138A5B);
  static const warn = Color(0xFFB7791F);

  // Sombre
  static const darkBg = Color(0xFF0B0E24);
  static const darkSurface = Color(0xFF141836);
  static const darkLine = Color(0xFF262C55);
  static const darkPrimary = Color(0xFF7F8CFF);
  static const darkRed = Color(0xFFFF6B72);

  static const hero = LinearGradient(
    colors: [blueDeep, blue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Rayons : une hiérarchie claire (le héros est plus arrondi que les cartes, les cartes que les champs).
class EdRadius {
  static const double control = 14;
  static const double card = 20;
  static const double hero = 28;
}

/// Mise en page adaptative : téléphone < 840 px, tablette / ordinateur ≥ 840 px.
class EdLayout {
  static const double wide = 840;
  static const double maxContent = 1040;
}
