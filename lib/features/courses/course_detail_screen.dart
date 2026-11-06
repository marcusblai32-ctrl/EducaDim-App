import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import 'course_repository.dart';
import 'course_widgets.dart';
import 'models.dart';
import 'offline_course_service.dart';
import 'progress_service.dart';

class CourseDetailScreen extends StatelessWidget {
  const CourseDetailScreen(this.courseId, {super.key});
  final int courseId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CourseRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Formation')),
      body: AsyncView<Loaded<CourseDetail>>(
        load: () => repo.detail(courseId),
        builder: (context, r, reload) => _Body(r.value, r.fromCache, reload),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.d, this.fromCache, this.reload);
  final CourseDetail d;
  final bool fromCache;
  final Future<void> Function() reload;

  String _statusText(String? s) => switch (s) {
        'pending' => 'Votre demande d’inscription est en attente de validation.',
        'rejected' => 'Votre demande d’inscription a été refusée.',
        'cancelled' => 'Votre inscription a été annulée.',
        _ => 'Inscrivez-vous ou activez un abonnement pour accéder au contenu.',
      };

  @override
  Widget build(BuildContext context) {
    final c = d.course;
    final t = Theme.of(context);
    final offline = context.watch<OfflineCourseService>();
    final repo = context.read<CourseRepository>();
    final busy = offline.busyCourseId == c.id;
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (fromCache) const OfflineBanner(),
        HeroCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Eyebrow('${c.categorie ?? 'Formation'} · ${c.niveau ?? ''}',
                color: const Color(0xFF83DCE5)),
            const SizedBox(height: 8),
            Text(c.titre,
                style: const TextStyle(
                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                '${c.duree} h · ${d.unitesCount} unité(s) · ${d.quizzesCount} quiz · ${d.flashcardsCount} flashcards',
                style: const TextStyle(color: Color(0xFFD3E2E9), fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 14),
        if (c.description.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(c.description, style: t.textTheme.bodyMedium?.copyWith(height: 1.6)),
            ),
          ),
        if (d.prerequisites.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Prérequis', style: t.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final p in d.prerequisites)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                        p.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: p.completed ? EdColors.good : null),
                    title: Text(p.titre),
                    subtitle: Text(p.obligatoire ? 'Obligatoire' : 'Recommandé'),
                    onTap: () => context.push('/course/${p.courseId}'),
                  ),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (!c.access.hasAccess)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Accès au contenu', style: t.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(_statusText(c.access.enrollmentStatus)),
                const SizedBox(height: 4),
                Text('Tarif : ${c.prixLabel}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => launchUrl(
                    Uri.parse('${ApiConfig.siteUrl}/fr/cours/'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('S’inscrire sur le site EducaDim'),
                ),
              ]),
            ),
          )
        else ...[
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(offline.isOffline(c.id)
                        ? Icons.offline_pin
                        : Icons.download_for_offline_outlined),
                label: Text(busy
                    ? '${offline.progressDone}/${offline.progressTotal}'
                    : offline.isOffline(c.id)
                        ? 'Disponible hors ligne'
                        : 'Télécharger le cours'),
                onPressed: busy
                    ? null
                    : () async {
                        final msg = ScaffoldMessenger.of(context);
                        try {
                          if (offline.isOffline(c.id)) {
                            await offline.remove(c.id);
                            msg.showSnackBar(const SnackBar(
                                content: Text('Téléchargement supprimé.')));
                          } else {
                            await offline.download(c.id, c.titre);
                            msg.showSnackBar(const SnackBar(
                                content: Text('Cours disponible hors ligne (textes et structure).')));
                          }
                        } catch (e) {
                          msg.showSnackBar(
                              SnackBar(content: Text(ApiException.from(e).message)));
                        }
                      },
              ),
            ),
          ]),
          if (d.quizzesCount > 0) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.quiz_outlined),
                title: const Text('Quiz'),
                subtitle: Text('${d.quizzesCount} quiz disponible(s)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/course/${c.id}/quizzes'),
              ),
            ),
          ],
          if (d.flashcardsCount > 0) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.style_outlined),
                title: const Text('Flashcards'),
                subtitle: Text('${d.flashcardsCount} carte(s) à réviser'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/flashcards/${c.id}'),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _CurriculumCard(c.id, repo),
        ],
      ]),
    );
  }
}

class _CurriculumCard extends StatelessWidget {
  const _CurriculumCard(this.courseId, this.repo);
  final int courseId;
  final CourseRepository repo;

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressService>();
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Programme', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<Loaded<Curriculum>>(
            future: repo.curriculum(courseId),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return Text(ApiException.from(snap.error!).message);
              }
              final cur = snap.data!.value;
              final total = cur.allLessons.length;
              final done = cur.allLessons.where((l) => progress.isDone(l.id)).length;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (total > 0) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                        value: done / total,
                        minHeight: 7,
                        color: EdColors.red,
                        backgroundColor: t.dividerColor),
                  ),
                  const SizedBox(height: 6),
                  Text('$done / $total leçon(s) terminée(s) sur cet appareil',
                      style: const TextStyle(fontSize: 12)),
                ],
                for (final u in cur.unites) ...[
                  const SizedBox(height: 14),
                  Text(u.titre, style: const TextStyle(fontWeight: FontWeight.w800)),
                  for (final m in u.modules) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(m.titre,
                          style: TextStyle(
                              color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
                    ),
                    for (final l in m.lecons)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                            progress.isDone(l.id) ? Icons.check_circle : Icons.play_circle_outline,
                            color: progress.isDone(l.id) ? EdColors.good : EdColors.blue),
                        title: Text(l.titre),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/lesson/${l.id}'),
                      ),
                  ],
                ],
                if (total == 0) const Text('Aucune leçon active pour ce cours.'),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
