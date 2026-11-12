import 'dart:math' as math;
import 'dart:typed_data';

import '../alerts/alert_service.dart';
import 'sfx_backend.dart';

/// Sons de l'interface, synthétisés (aucun fichier audio à embarquer) :
/// succès (réussite), échec (non réussi), terminé (leçon marquée terminée).
/// Respecte le réglage « Sons des notifications et rappels ».
abstract final class Sfx {
  static final Map<String, Uint8List> _cache = {};

  static Future<void> success() => _play('success', const [
        _N(523, 90), _N(659, 90), _N(784, 90), _N(1047, 380),
      ]);

  static Future<void> fail() => _play('fail', const [
        _N(311, 190, rich: true), _N(233, 380, rich: true),
      ]);

  static Future<void> received() => _play('received', const [
        _N(880, 110), _N(1175, 240),
      ]);

  static Future<void> sent() => _play('sent', const [
        _N(740, 50), _N(988, 130),
      ]);

  static Future<void> complete() => _play('complete', const [
        _N(587, 60), _N(880, 220),
      ]);

  static Future<void> _play(String key, List<_N> notes) async {
    if (!AlertService.instance.soundEnabled) return;
    try {
      final bytes = _cache.putIfAbsent(key, () => _wav(notes));
      await playWav(key, bytes);
    } catch (_) {}
  }

  static Uint8List _wav(List<_N> notes) {
    const rate = 22050;
    final total = notes.fold<int>(0, (s, n) => s + (rate * n.ms / 1000).round());
    final data = ByteData(44 + total * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + total * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, total * 2, Endian.little);
    var pos = 44;
    for (final n in notes) {
      final count = (rate * n.ms / 1000).round();
      for (var i = 0; i < count; i++) {
        final t = i / rate;
        final env = math.min(1.0, i / (rate * 0.004)) * math.exp(-3.0 * i / count);
        var s = math.sin(2 * math.pi * n.hz * t) + 0.3 * math.sin(2 * math.pi * n.hz * 2 * t);
        if (n.rich) s += 0.5 * math.sin(2 * math.pi * n.hz * 3 * t) + 0.3 * math.sin(2 * math.pi * n.hz * 5 * t);
        final v = (s * env * 0.32 * 32767).round().clamp(-32767, 32767);
        data.setInt16(pos, v, Endian.little);
        pos += 2;
      }
    }
    return data.buffer.asUint8List();
  }
}

class _N {
  const _N(this.hz, this.ms, {this.rich = false});
  final double hz;
  final int ms;
  final bool rich;
}
