import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Lecture d'un son court (WAV). Version de base : simple clic système.
/// Le workflow Android remplace ce fichier par une version qui joue vraiment le son
/// (voir tool/sfx_backend_audioplayers.dart.txt) quand le paquet audio est disponible.
Future<void> playWav(String key, Uint8List bytes) async {
  try {
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {}
}
