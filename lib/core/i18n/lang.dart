import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'strings_ht.dart';

/// Langue de l'application : « fr » (français) ou « ht » (kreyòl).
/// Les textes sources sont en français ; la table `htStrings` donne le kreyòl.
/// La langue est aussi envoyée au serveur (Accept-Language) pour le contenu des cours.
class Lang extends ChangeNotifier {
  Lang._();
  static final Lang instance = Lang._();
  static const _key = 'app_lang';

  String _code = 'fr';
  SharedPreferences? _prefs;

  String get code => _code;
  bool get isHt => _code == 'ht';

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    final saved = prefs.getString(_key);
    if (saved == 'fr' || saved == 'ht') {
      _code = saved!;
    } else {
      // Première ouverture : langue de l'appareil si c'est le kreyòl, sinon français.
      final device = ui.PlatformDispatcher.instance.locale.languageCode;
      _code = device == 'ht' ? 'ht' : 'fr';
    }
  }

  Future<void> set(String code) async {
    if (code != 'fr' && code != 'ht') return;
    if (code == _code) return;
    _code = code;
    await _prefs?.setString(_key, code);
    notifyListeners();
  }
}

/// Traduit un texte source français. `{nom}` est remplacé par `args['nom']`.
String tr(String fr, [Map<String, Object?>? args]) {
  var s = Lang.instance.isHt ? (htStrings[fr] ?? fr) : fr;
  if (args != null) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  }
  return s;
}
