import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_client.dart';

class TeacherComment {
  TeacherComment(this.id, this.text, this.createdAt, this.personal);
  final int id;
  final String text;
  final DateTime? createdAt;
  final bool personal;
}

class CourseMessages {
  CourseMessages({
    required this.courseId,
    required this.title,
    required this.headcount,
    required this.groupUrl,
    required this.teacherUrl,
    required this.comments,
  });
  final int courseId;
  final String title;
  final int headcount;
  final String groupUrl;
  final String teacherUrl;
  final List<TeacherComment> comments;
}

/// Messages du professeur par cours (lecture seule). UN seul appel GET comments/ au plus toutes les 24 h
/// (au démarrage ou au retour dans l'application) ; le résultat reste sur le téléphone, lisible hors ligne.
class CommentsService extends ChangeNotifier {
  CommentsService(this._api, this._prefs) {
    _loadLocal();
  }
  final ApiClient _api;
  final SharedPreferences _prefs;

  static const _kData = 'course_messages_v1';
  static const _kAt = 'course_messages_at_v1';
  static const _day = Duration(hours: 24);
  static const _manual = Duration(hours: 1);

  List<CourseMessages> courses = [];
  bool loading = false;
  DateTime? lastFetch;

  void _loadLocal() {
    try {
      final at = _prefs.getString(_kAt);
      lastFetch = at == null ? null : DateTime.tryParse(at);
      final raw = _prefs.getString(_kData);
      if (raw != null) courses = _parse(jsonDecode(raw));
    } catch (_) {
      courses = [];
    }
  }

  List<CourseMessages> _parse(dynamic data) {
    final list = data is Map ? (data['courses'] as List? ?? []) : const [];
    return [
      for (final c in list)
        if (c is Map)
          CourseMessages(
            courseId: (c['course_id'] as num).toInt(),
            title: '${c['title'] ?? ''}',
            headcount: (c['headcount'] as num?)?.toInt() ?? 0,
            groupUrl: '${c['group_url'] ?? ''}',
            teacherUrl: '${c['teacher_url'] ?? ''}',
            comments: [
              for (final x in (c['comments'] as List? ?? []))
                if (x is Map)
                  TeacherComment((x['id'] as num).toInt(), '${x['text'] ?? ''}',
                      DateTime.tryParse('${x['created_at'] ?? ''}')?.toLocal(), x['personal'] == true),
            ],
          ),
    ];
  }

  bool get dueDaily => lastFetch == null || DateTime.now().difference(lastFetch!) > _day;
  bool get canRefreshManually => lastFetch == null || DateTime.now().difference(lastFetch!) > _manual;

  /// Appel automatique : au plus une fois par 24 h.
  Future<void> maybeFetch() async {
    if (dueDaily) await fetch();
  }

  Future<void> fetch() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final res = await _api.dio.get('comments/');
      final data = res.data;
      final fresh = _parse(data);
      // Conserve les anciens messages déjà lus sur le téléphone (le serveur renvoie tout, mais on reste sûr).
      courses = fresh;
      lastFetch = DateTime.now();
      await _prefs.setString(_kData, jsonEncode(_toJson(fresh)));
      await _prefs.setString(_kAt, lastFetch!.toIso8601String());
    } on DioException catch (_) {
      // hors ligne : on garde ce qui est déjà sur le téléphone, on réessaiera plus tard
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Map<String, dynamic> _toJson(List<CourseMessages> list) => {
        'courses': [
          for (final c in list)
            {
              'course_id': c.courseId,
              'title': c.title,
              'headcount': c.headcount,
              'group_url': c.groupUrl,
              'teacher_url': c.teacherUrl,
              'comments': [
                for (final x in c.comments)
                  {
                    'id': x.id,
                    'text': x.text,
                    'created_at': x.createdAt?.toUtc().toIso8601String(),
                    'personal': x.personal,
                  }
              ],
            }
        ],
      };

  /// Changement de compte : on oublie les messages de l'ancien compte.
  Future<void> reset() async {
    courses = [];
    lastFetch = null;
    await _prefs.remove(_kData);
    await _prefs.remove(_kAt);
    notifyListeners();
  }
}
