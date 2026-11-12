import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../i18n/lang.dart';

/// Alertes sonores (notifications, messages) et rappels d'étude programmés.
/// Les rappels sont planifiés sur l'appareil : ils sonnent même quand l'application est fermée.
/// Les notifications et messages du serveur sonnent lorsque l'application est ouverte.
class AlertService {
  AlertService._();
  static final AlertService instance = AlertService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  SharedPreferences? _prefs;
  bool _ready = false;
  bool soundEnabled = true;
  int _seq = 100;

  static const _soundKey = 'alert_sound';
  static const _reminderBase = 9000;
  static const _reminderSlots = 30;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    soundEnabled = prefs.getBool(_soundKey) ?? true;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // iOS : la permission est demandée plus tard (requestPermission), pas au lancement.
          iOS: DarwinInitializationSettings(
              requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false; // réessayé plus tard
    }
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return (await ios.requestPermissions(alert: true, badge: true, sound: true)) ?? false;
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return (await android?.requestNotificationsPermission()) ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setSound(bool v) async {
    soundEnabled = v;
    await _prefs?.setBool(_soundKey, v);
  }

  // Le son d'un canal Android ne peut plus changer une fois créé : un canal par état du son.
  NotificationDetails _details(String channel, String name, {bool smallIcon = true}) {
    final id = '${channel}_${soundEnabled ? 's' : 'q'}';
    return NotificationDetails(
      android: AndroidNotificationDetails(
        id,
        name,
        importance: Importance.max, // bulle qui s'affiche au-dessus du rideau (heads-up)
        priority: Priority.max,
        playSound: soundEnabled,
        enableVibration: soundEnabled,
        icon: smallIcon ? 'ic_stat_educadim' : null,
        color: const Color(0xFF1E40AF),
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        ticker: name,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: soundEnabled),
    );
  }

  /// Notification immédiate avec son (nouvelle notification, nouveau message…).
  /// Retourne null si OK, sinon une raison lisible (permission refusée, etc.).
  Future<String?> notify(String title, String body) async {
    if (!_ready) {
      await _retryInit();
      if (!_ready) return tr('Les notifications ne sont pas disponibles sur cet appareil.');
    }
    try {
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await android?.areNotificationsEnabled();
      if (enabled == false) {
        final granted = await android?.requestNotificationsPermission();
        if (granted != true) {
          return tr('Les notifications sont désactivées pour EducaDim. Activez-les dans les paramètres Android.');
        }
      }
    } catch (_) {}
    _seq = _seq >= 899 ? 100 : _seq + 1;
    for (final small in [true, false]) {
      try {
        await _plugin.show(
            _seq, title, body, _details('alerts', tr('Notifications et messages'), smallIcon: small));
        return null;
      } catch (_) {
        // icône de statut absente : on réessaie avec l'icône de l'application
      }
    }
    return tr('Impossible d’afficher la notification.');
  }

  Future<void> _retryInit() async {
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // iOS : la permission est demandée plus tard (requestPermission), pas au lancement.
          iOS: DarwinInitializationSettings(
              requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
      );
      _ready = true;
    } catch (_) {}
  }

  Future<void> cancelReminders() async {
    if (!_ready) return;
    try {
      for (var i = 0; i < _reminderSlots; i++) {
        await _plugin.cancel(_reminderBase + i);
      }
    } catch (_) {}
  }

  /// Programme les rappels des 3 prochaines semaines aux jours/heure choisis.
  /// `weekdays` : lundi = 0 … dimanche = 6. Si l'apprenant s'est déjà connecté aujourd'hui,
  /// le rappel d'aujourd'hui est supprimé.
  Future<void> scheduleReminders({
    required Set<int> weekdays,
    required int hour,
    required int minute,
    required int streak,
    required bool checkedToday,
  }) async {
    if (!_ready) return;
    try {
      await cancelReminders();
      if (weekdays.isEmpty) return;
      final now = DateTime.now();
      final title = tr('C’est l’heure d’apprendre !');
      final body = streak > 0
          ? tr('Votre série de {n} jours vous attend. Connectez-vous aujourd’hui pour la garder !', {'n': streak})
          : tr('Prenez quelques minutes pour avancer dans vos cours.');
      for (var i = 0; i < 21; i++) {
        final day = DateTime(now.year, now.month, now.day + i);
        if (!weekdays.contains(day.weekday - 1)) continue;
        if (i == 0 && checkedToday) continue;
        final at = DateTime(day.year, day.month, day.day, hour, minute);
        if (!at.isAfter(now.add(const Duration(seconds: 30)))) continue;
        for (final small in [true, false]) {
          try {
            await _plugin.zonedSchedule(
              _reminderBase + i,
              title,
              body,
              tz.TZDateTime.from(at, tz.UTC), // instant absolu : indépendant du fuseau
              _details('reminders', tr('Rappels d’étude'), smallIcon: small),
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
            break;
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
