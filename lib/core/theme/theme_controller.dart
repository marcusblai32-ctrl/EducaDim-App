import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) {
    final v = _prefs.getString(_key);
    _mode = ThemeMode.values.firstWhere(
      (m) => m.name == v,
      orElse: () => ThemeMode.system,
    );
  }
  static const _key = 'theme_mode';
  final SharedPreferences _prefs;
  late ThemeMode _mode;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    await _prefs.setString(_key, m.name);
  }
}
