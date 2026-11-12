import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
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
  bool _tzReady = false;
  /// Dernière erreur de programmation (affichée par le bouton de test des rappels).
  String? lastError;

  /// Vrai si la programmation système a échoué : l'application prend alors le relais quand elle est ouverte.
  bool scheduleBroken = false;

  /// Titre et texte d'un rappel d'étude.
  List<String> reminderText(int streak) => [
        tr('C’est l’heure d’apprendre !'),
        streak > 0
            ? tr('Votre série de {n} jours vous attend. Connectez-vous aujourd’hui pour la garder !', {'n': streak})
            : tr('Prenez quelques minutes pour avancer dans vos cours.'),
      ];

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

  // Le son d'un canal Android ne peut plus changer une fois créé : un canal par type de notification
  // (message, notification, rappel) et par état du son. « v2 » = canaux avec sons personnalisés.
  static const _rawSounds = {'message': 'snd_message', 'notif': 'snd_notification', 'reminder': 'snd_reminder'};

  NotificationDetails _details(String kind, String name, {bool smallIcon = true}) {
    final id = '${kind}_v2_${soundEnabled ? 's' : 'q'}';
    final raw = _rawSounds[kind];
    return NotificationDetails(
      android: AndroidNotificationDetails(
        id,
        name,
        importance: Importance.max, // bulle qui s'affiche au-dessus du rideau (heads-up)
        priority: Priority.max,
        playSound: soundEnabled,
        sound: soundEnabled && raw != null ? RawResourceAndroidNotificationSound(raw) : null,
        enableVibration: soundEnabled,
        icon: smallIcon ? 'ic_stat_educadim' : null,
        color: const Color(0xFF1E40AF),
        category: kind == 'reminder' ? AndroidNotificationCategory.reminder : AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        ticker: name,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: soundEnabled),
    );
  }

  /// Notification immédiate avec son (nouvelle notification, nouveau message…).
  /// Retourne null si OK, sinon une raison lisible (permission refusée, etc.).
  Future<String?> notify(String title, String body, {String kind = 'notif'}) async {
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
        await _plugin.show(_seq, title, body,
            _details(kind, kind == 'message' ? tr('Messages') : tr('Notifications'), smallIcon: small));
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
  /// `weekdays` : lundi = 0 … dimanche = 6. Le rappel sonne à l'heure choisie,
  /// même si l'application a déjà été ouverte aujourd'hui.
  Future<void> scheduleReminders({
    required Set<int> weekdays,
    required int hour,
    required int minute,
    required int streak,
    required bool checkedToday,
  }) async {
    if (!_ready) await _retryInit();
    if (!_ready) {
      lastError = 'init';
      return;
    }
    lastError = null;
    if (!_tzReady) {
      try {
        tzdata.initializeTimeZones();
      } catch (_) {}
      _tzReady = true;
    }
    try {
      await cancelReminders();
      if (weekdays.isEmpty) return;
      // Android 13+ : sans permission, la programmation est ignorée.
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.areNotificationsEnabled() == false) {
        await android?.requestNotificationsPermission();
      }
      final now = DateTime.now();
      final texts = reminderText(streak);
      final title = texts[0];
      final body = texts[1];
      var exact = false;
      try {
        exact = await android?.canScheduleExactNotifications() ?? false;
      } catch (_) {}
      var planned = 0;
      for (var i = 0; i < 21; i++) {
        final day = DateTime(now.year, now.month, now.day + i);
        if (!weekdays.contains(day.weekday - 1)) continue;
        final at = DateTime(day.year, day.month, day.day, hour, minute);
        if (!at.isAfter(now.add(const Duration(seconds: 30)))) continue;
        if (await _scheduleOne(_reminderBase + i, title, body, at, exact: exact)) planned++;
      }
      // Vérification : les rappels sont-ils vraiment enregistrés dans le système ?
      final pending = planned == 0 ? 0 : await pendingCount();
      scheduleBroken = planned > 0 && pending == 0;
    } catch (e) {
      lastError = '$e';
    }
  }

  /// Programme une notification à `at` ; essaie plusieurs combinaisons (icône, mode d'alarme).
  Future<bool> _scheduleOne(int id, String title, String body, DateTime at, {bool exact = false}) async {
    final when = tz.TZDateTime.from(at.toUtc(), tz.UTC); // instant absolu : indépendant du fuseau
    for (final mode in [
      if (exact) AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
      AndroidScheduleMode.inexact,
    ]) {
      for (final small in [true, false]) {
        try {
          await _plugin.zonedSchedule(
            id,
            title,
            body,
            when,
            _details('reminder', tr('Rappels d’étude'), smallIcon: small),
            androidScheduleMode: mode,
          );
          return true;
        } catch (e) {
          lastError = '$e';
        }
      }
    }
    return false;
  }

  /// Nombre de rappels réellement enregistrés dans le système (-1 si inconnu).
  Future<int> pendingCount() async {
    try {
      final list = await _plugin.pendingNotificationRequests();
      return list.where((r) => r.id >= _reminderBase && r.id < _reminderBase + _reminderSlots).length;
    } catch (_) {
      return -1;
    }
  }

  /// Résumé lisible de l'état des rappels (affiché dans Profil) pour comprendre un éventuel blocage.
  Future<String> statusLine() async {
    if (!_ready) await _retryInit();
    if (!_ready) return tr('Notifications indisponibles (initialisation échouée).');
    String perm = '?';
    String exact = '?';
    try {
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (a != null) {
        perm = (await a.areNotificationsEnabled()) == true ? 'oui' : 'non';
        exact = (await a.canScheduleExactNotifications()) == true ? 'oui' : 'non';
      }
    } catch (_) {}
    final n = await pendingCount();
    final err = lastError == null ? '' : ' · erreur : ${lastError!.length > 120 ? lastError!.substring(0, 120) : lastError}';
    return '${tr('Rappels programmés')} : $n · ${tr('notifications autorisées')} : $perm · ${tr('alarmes exactes')} : $exact$err';
  }
}
