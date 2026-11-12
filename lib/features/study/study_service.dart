import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/alerts/alert_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class StudyDay {
  StudyDay(this.date, this.planned, this.done, this.today);
  final DateTime date;
  final bool planned, done, today;
}

class LeaderRow {
  LeaderRow(this.rank, this.name, this.streak, this.online, this.me);
  final int rank, streak;
  final String name;
  final bool online, me;
}

class LeaderData {
  LeaderData(this.rows, this.myRank, this.myStreak);
  final List<LeaderRow> rows;
  final int? myRank;
  final int myStreak;
}

/// Rythme d'étude, série de jours d'affilée et présence en ligne.
/// Le serveur calcule la série (règle : un jour PRÉVU sans connexion remet la série à zéro) ;
/// l'application envoie un signal de présence chaque minute (au premier plan) et programme
/// les rappels sur l'appareil.
class StudyService extends ChangeNotifier {
  StudyService(this._api, this._prefs) {
    _restoreLocal();
  }
  final ApiClient _api;
  final SharedPreferences _prefs;

  bool loaded = false;
  bool hasPlan = false;
  Set<int> weekdays = {}; // lundi = 0 … dimanche = 6
  int hour = 18, minute = 0;
  bool showInRanking = true;
  int streak = 0, best = 0;
  bool checkedToday = false;
  List<StudyDay> week = [];
  bool streakLost = false;

  /// Appelé quand le serveur vient de féliciter l'utilisateur (nouvelle notification à récupérer).
  void Function()? onAward;

  bool get needsOnboarding => loaded && !hasPlan;
  TimeOfDay get time => TimeOfDay(hour: hour, minute: minute);

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;
  bool Function()? _loggedIn;

  void _restoreLocal() {
    final d = _prefs.getString('study_days');
    if (d != null && d.isNotEmpty) {
      weekdays = d.split(',').map(int.parse).toSet();
      hour = _prefs.getInt('study_hour') ?? 18;
      minute = _prefs.getInt('study_min') ?? 0;
      hasPlan = true;
      loaded = true; // plan connu hors ligne
    }
    streak = _prefs.getInt('study_streak') ?? 0;
  }

  void start(bool Function() loggedIn) {
    _loggedIn = loggedIn;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_foreground) _fallbackReminder();
      if (_foreground && (_loggedIn?.call() ?? false)) ping();
    });
    // Rappels programmés depuis le plan enregistré sur l'appareil (même sans réseau).
    if (hasPlan) unawaited(_schedule());
    _lifecycle ??= AppLifecycleListener(
      onResume: () {
        _foreground = true;
        if (_loggedIn?.call() ?? false) ping();
      },
      onPause: () => _foreground = false,
    );
  }

  Future<void> reset() async {
    for (final k in ['study_days', 'study_hour', 'study_min', 'study_streak']) {
      await _prefs.remove(k);
    }
    weekdays = {};
    hasPlan = false;
    loaded = false;
    streak = 0;
    best = 0;
    checkedToday = false;
    week = [];
    streakLost = false;
    await AlertService.instance.cancelReminders();
    notifyListeners();
  }

  /// Filet de sécurité : si la programmation système a échoué, l'application ouverte sonne le rappel à l'heure.
  void _fallbackReminder() {
    if (!hasPlan || checkedToday || !AlertService.instance.scheduleBroken) return;
    final now = DateTime.now();
    if (!weekdays.contains(now.weekday - 1)) return;
    final at = DateTime(now.year, now.month, now.day, hour, minute);
    if (now.isBefore(at) || now.isAfter(at.add(const Duration(minutes: 10)))) return;
    final key = '${now.year}-${now.month}-${now.day}';
    if (_prefs.getString('study_fb_date') == key) return;
    _prefs.setString('study_fb_date', key);
    final t = AlertService.instance.reminderText(streak);
    AlertService.instance.notify(t[0], t[1], kind: 'reminder');
  }

  void dismissLost() {
    streakLost = false;
    notifyListeners();
  }

  void _apply(Map d) {
    final plan = d['plan'];
    if (plan is Map) {
      weekdays = (plan['weekdays'] as List? ?? []).whereType<int>().toSet();
      final t = (plan['time'] as String? ?? '18:00').split(':');
      hour = int.tryParse(t.first) ?? 18;
      minute = t.length > 1 ? int.tryParse(t[1]) ?? 0 : 0;
      showInRanking = plan['show_in_ranking'] != false;
      hasPlan = weekdays.isNotEmpty;
    } else {
      hasPlan = false;
      weekdays = {};
    }
    final before = streak;
    streak = d['streak'] is int ? d['streak'] as int : 0;
    best = d['best'] is int ? d['best'] as int : 0;
    checkedToday = d['checked_today'] == true;
    streakLost = before > 0 && streak == 0 && !checkedToday ? true : (streak > 0 ? false : streakLost);
    week = [
      for (final w in (d['week'] as List? ?? []))
        if (w is Map && DateTime.tryParse('${w['date']}') != null)
          StudyDay(DateTime.parse('${w['date']}'), w['planned'] == true, w['done'] == true, w['today'] == true),
    ];
    loaded = true;
    if (hasPlan) {
      _prefs.setString('study_days', (weekdays.toList()..sort()).join(','));
      _prefs.setInt('study_hour', hour);
      _prefs.setInt('study_min', minute);
    } else {
      _prefs.remove('study_days');
    }
    _prefs.setInt('study_streak', streak);
    unawaited(_schedule());
    notifyListeners();
  }

  Future<void> _schedule() => hasPlan
      ? AlertService.instance.scheduleReminders(
          weekdays: weekdays, hour: hour, minute: minute, streak: streak, checkedToday: checkedToday)
      : AlertService.instance.cancelReminders();

  Future<void> load() async {
    try {
      final res = await _api.dio.get('study/');
      if (res.data is Map) _apply(res.data as Map);
    } on DioException {
      // hors ligne : on garde l'état local
    }
  }

  /// Signal de présence + connexion du jour (félicitations côté serveur si palier atteint).
  Future<void> ping() async {
    try {
      final res = await _api.dio.post('presence/ping/');
      if (res.data is Map) {
        final d = res.data as Map;
        _apply(d);
        if (d['award'] is Map) onAward?.call();
      }
    } on DioException {
      // pas de réseau : rien à faire
    }
  }

  Future<void> savePlan(Set<int> days, TimeOfDay t, bool ranking) async {
    try {
      final res = await _api.dio.put('study/plan/', data: {
        'weekdays': (days.toList()..sort()),
        'time': '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
        'show_in_ranking': ranking,
      });
      await AlertService.instance.requestPermission();
      if (res.data is Map) _apply(res.data as Map);
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  Future<LeaderData> leaderboard() async {
    try {
      final res = await _api.dio.get('streaks/leaderboard/');
      final m = res.data is Map ? res.data as Map : const {};
      final rows = [
        for (final r in (m['leaders'] as List? ?? []))
          if (r is Map)
            LeaderRow(r['rank'] as int? ?? 0, '${r['name'] ?? ''}', r['streak'] as int? ?? 0,
                r['online'] == true, r['me'] == true),
      ];
      final me = m['me'] is Map ? m['me'] as Map : const {};
      return LeaderData(rows, me['rank'] as int?, me['streak'] as int? ?? 0);
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
