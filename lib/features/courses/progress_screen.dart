import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import 'course_repository.dart';
import 'course_widgets.dart';
import 'models.dart';
import 'progress_service.dart';

class _Data {
  _Data(this.courses, this.progress, this.activity, this.note, this.fromCache);
  final List<Course> courses;
  final ProgressSummary? progress;
  final List<ActivityItem> activity;
  final String? note;
  final bool fromCache;
}

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  Future<_Data> _load(CourseRepository repo) async {
    final courses = await repo.myCourses();
    ProgressSummary? progress;
    var activity = <ActivityItem>[];
    String? note;
    var cache = courses.fromCache;
    try {
      final p = await repo.progress();
      progress = p.value;
      cache = cache || p.fromCache;
    } on ApiException catch (e) {
      note = e.statusCode == 404
          ? 'Le suivi serveur n’est pas encore disponible (mise à jour du backend nécessaire). '
              'Affichage de la progression locale.'
          : e.message;
    }
    try {
      activity = (await repo.activity()).value;
    } on ApiException {
      // activité facultative
    }
    return _Data(courses.value, progress, activity, note, cache);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CourseRepository>();
    final local = context.watch<ProgressService>();
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ma progression')),
      body: AsyncView<_Data>(
        load: () => _load(repo),
        builder: (context, d, reload) {
          final done = [d.progress?.lessonsDone ?? 0, local.totalCompleted]
              .reduce((a, b) => a > b ? a : b);
          final started = d.courses.where((c) {
            final pct = d.progress?.coursePct[c.id] ?? 0;
            return pct > 0 || local.doneInCourse(c.id) > 0;
          }).toList();
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (d.fromCache) const OfflineBanner(),
              HeroCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Eyebrow('Votre apprentissage', color: Color(0xFF83DCE5)),
                  const SizedBox(height: 8),
                  Text('$done leçon(s) terminée(s)',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('${started.length} cours en cours · ${d.courses.length} accessible(s)',
                      style: const TextStyle(color: Color(0xFFD3E2E9))),
                ]),
              ),
              if (d.note != null) ...[
                const SizedBox(height: 10),
                Text(d.note!, style: t.textTheme.bodySmall),
              ],
              const SizedBox(height: 18),
              Text('Mes cours', style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (started.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Terminez une leçon pour voir votre progression ici.'),
                ),
              for (final c in started)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(17),
                      onTap: () => context.push('/course/${c.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.titre, style: t.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          if (d.progress?.coursePct[c.id] != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: LinearProgressIndicator(
                                value: (d.progress!.coursePct[c.id]! / 100).clamp(0.0, 1.0).toDouble(),
                                minHeight: 8,
                                color: EdColors.red,
                                backgroundColor: t.dividerColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('${d.progress!.coursePct[c.id]!.toStringAsFixed(0)} %'
                                ' · ${local.doneInCourse(c.id)} leçon(s) sur cet appareil'),
                          ] else
                            Text('${local.doneInCourse(c.id)} leçon(s) terminée(s) sur cet appareil'),
                        ]),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text('Activités récentes', style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (d.activity.isEmpty)
                const Text('Aucune activité récente.')
              else
                for (final a in d.activity.take(15))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.history, color: EdColors.blue),
                    title: Text(a.description.isEmpty ? a.label : a.description),
                    subtitle: Text('${a.label} · ${formatDate(a.date)}'),
                  ),
            ]),
          );
        },
      ),
    );
  }
}
