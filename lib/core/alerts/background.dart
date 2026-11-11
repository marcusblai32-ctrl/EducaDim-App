import 'package:shared_preferences/shared_preferences.dart';

/// Le plugin d'arrière-plan (workmanager) est retiré : il ne compile pas avec la
/// version actuelle de Flutter. Les rappels d'étude programmés sonnent toujours
/// application fermée ; les nouveaux messages/notifications sonnent application ouverte.
class BackgroundAlerts {
  static Future<void> start() async {}
  static Future<void> stop() async {}
  static Future<void> markForeground(SharedPreferences prefs) async {}
}
