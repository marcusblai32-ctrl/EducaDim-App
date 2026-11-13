import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';

/// Notes de pratique musicale (application PPI), lues dans EducaDim : GET ppi/progress/ (lecture seule).
class PpiCourse {
  PpiCourse(this.title, this.practiced, this.total, this.completed, this.avg, this.minutes, this.items);
  final String title;
  final int practiced, total, completed, minutes;
  final double avg;
  final List<PpiItem> items;
}

class PpiItem {
  PpiItem(this.title, this.attempts, this.best, this.completed);
  final String title;
  final int attempts;
  final double best;
  final bool completed;
}

class PpiProgress {
  PpiProgress(this.courses, this.avg, this.done, this.exercises, this.minutes, this.attempts);
  final List<PpiCourse> courses;
  final double? avg;
  final int done, exercises, minutes, attempts;
}

double _d(dynamic v) => v is num ? v.toDouble() : 0;
int _i(dynamic v) => v is num ? v.toInt() : 0;

Future<PpiProgress> loadPpiProgress(ApiClient api) async {
  try {
    final res = await api.dio.get('ppi/progress/');
    final m = res.data is Map ? res.data as Map : const {};
    final t = m['totals'] is Map ? m['totals'] as Map : const {};
    final courses = <PpiCourse>[
      for (final c in (m['courses'] as List? ?? []))
        if (c is Map)
          PpiCourse(
            '${c['course_title'] ?? ''}',
            _i(c['practiced']),
            _i(c['total']),
            _i(c['completed']),
            _d(c['avg']),
            _i(c['minutes']),
            [
              for (final x in (c['items'] as List? ?? []))
                if (x is Map)
                  PpiItem('${x['title'] ?? ''}', _i(x['attempts']), _d(x['best']), x['completed'] == true),
            ],
          ),
    ];
    return PpiProgress(courses, t['avg'] is num ? _d(t['avg']) : null, _i(t['completed']),
        _i(t['exercises']), _i(t['minutes']), _i(t['attempts']));
  } on DioException catch (e) {
    throw mapDio(e);
  }
}

class PpiProgressScreen extends StatelessWidget {
  const PpiProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.65);
    Widget stat(String value, String label) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              child: Column(children: [
                Text(value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 11.5, color: muted), textAlign: TextAlign.center),
              ]),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Pratique musicale')),
      body: AsyncView<PpiProgress>(
        load: () => loadPpiProgress(api),
        builder: (context, p, reload) {
          if (p.courses.isEmpty) {
            return const EmptyState(
                icon: Icons.piano_rounded,
                title: 'Aucune pratique pour le moment',
                message: 'Ouvrez l’application PPI et terminez un exercice : vos notes apparaîtront ici.');
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                stat(p.avg == null ? '–' : '${p.avg!.round()} %', 'Précision moyenne'),
                const SizedBox(width: 8),
                stat('${p.done}/${p.exercises}', 'Exercices réussis'),
                const SizedBox(width: 8),
                stat('${p.minutes} min', 'Temps de pratique'),
              ]),
              const SizedBox(height: 16),
              for (final c in p.courses) ...[
                Text(c.title, style: t.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(tr('{a}/{b} exercices réussis · précision {p} %', {'a': c.completed, 'b': c.total, 'p': c.avg.round()}),
                    style: TextStyle(color: muted)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(minHeight: 8, value: (c.avg / 100).clamp(0.0, 1.0).toDouble()),
                ),
                const SizedBox(height: 8),
                for (final i in c.items)
                  Card(
                    child: ListTile(
                      leading: Icon(i.completed ? Icons.check_circle_rounded : Icons.timelapse_rounded,
                          color: i.completed ? EdColors.good : muted),
                      title: Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(tr('{n} essai(s)', {'n': i.attempts})),
                      trailing: Text('${i.best.round()} %', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ]),
          );
        },
      ),
    );
  }
}
