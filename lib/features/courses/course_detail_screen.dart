import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/api_config.dart';
import '../../core/i18n/text.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/net_image.dart';
import '../chat/chat_controller.dart';
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
        load: () async {
          final r = await repo.detail(courseId);
          if (!r.fromCache && !r.value.course.estPayant && r.value.course.access.source == 'free') {
            repo.enrollFree(courseId);
          }
          return r;
        },
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
        'pending' => tr('Votre demande d’inscription est en attente de validation.'),
        'rejected' => tr('Votre demande d’inscription a été refusée.'),
        'cancelled' => tr('Votre inscription a été annulée.'),
        _ => tr('Inscrivez-vous ou activez un abonnement pour accéder au contenu.'),
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
      child: ListView(padding: EdgeInsets.zero, children: [
        // ---- Image d'en-tête (remplit toute la largeur) + titre ----
        Stack(children: [
          NetImage(c.image, aspectRatio: 16 / 9),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
                  stops: const [0.35, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow('${c.categorie ?? tr('Formation')}${c.niveau != null ? ' · ${c.niveau}' : ''}',
                  color: const Color(0xFFB9C2FF)),
              const SizedBox(height: 6),
              Text(c.titre,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
            ]),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (fromCache) const OfflineBanner(),
            // ---- Chiffres clés ----
            Row(children: [
              Expanded(child: StatTile('Durée', '${c.duree} h', icon: Icons.schedule_rounded)),
              const SizedBox(width: 10),
              Expanded(child: StatTile('Unités', '${d.unitesCount}', icon: Icons.folder_open_rounded)),
              const SizedBox(width: 10),
              Expanded(child: StatTile('Quiz', '${d.quizzesCount}', icon: Icons.quiz_outlined)),
            ]),
            if (c.description.isNotEmpty) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(c.description, style: t.textTheme.bodyMedium?.copyWith(height: 1.6)),
                ),
              ),
            ],
            if (d.prerequisites.isNotEmpty) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Prérequis', style: t.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    for (final p in d.prerequisites)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(p.completed ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
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
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.lock_outline_rounded, color: t.colorScheme.secondary),
                      const SizedBox(width: 10),
                      Text('Accès au contenu', style: t.textTheme.titleMedium),
                    ]),
                    const SizedBox(height: 10),
                    Text(_statusText(c.access.enrollmentStatus)),
                    const SizedBox(height: 6),
                    Text(tr('Tarif : {p}', {'p': c.prixLabel}), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => launchUrl(Uri.parse('${ApiConfig.siteUrl}/fr/cours/${c.id}/'),
                          mode: LaunchMode.externalApplication),
                      child: const Text('S’inscrire et payer sur le site'),
                    ),
                  ]),
                ),
              )
            else ...[
              OutlinedButton.icon(
                icon: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(offline.isOffline(c.id) ? Icons.offline_pin_rounded : Icons.download_for_offline_outlined),
                label: Text(busy
                    ? '${offline.progressDone}/${offline.progressTotal}'
                    : offline.isOffline(c.id)
                        ? tr('Disponible hors ligne')
                        : tr('Télécharger le cours')),
                onPressed: busy
                    ? null
                    : () async {
                        final msg = ScaffoldMessenger.of(context);
                        try {
                          if (offline.isOffline(c.id)) {
                            await offline.remove(c.id);
                            msg.showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, SnackBar(content: Text(tr('Téléchargement supprimé.'))));
                          } else {
                            await offline.download(c.id, c.titre);
                            msg.showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, SnackBar(
                                content: Text(tr('Cours disponible hors ligne (textes et structure).'))));
                          }
                        } catch (e) {
                          msg.showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, SnackBar(content: Text(ApiException.from(e).message)));
                        }
                      },
              ),
              const SizedBox(height: 10),
              _Action(Icons.forum_outlined, 'Discussion du cours', 'Échangez avec les autres apprenants',
                  () async {
                final msg = ScaffoldMessenger.of(context);
                final nav = GoRouter.of(context);
                try {
                  final id = await context.read<ChatController>().openCourseRoom(c.id);
                  nav.push('/chat/$id', extra: '${tr('Groupe')} - ${c.titre}');
                } on ApiException catch (e) {
                  msg.showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, SnackBar(
                      content: Text(e.isOffline
                          ? tr('Connexion requise pour ouvrir la discussion.')
                          : e.message)));
                }
              }),
              if (d.quizzesCount > 0) ...[
                const SizedBox(height: 10),
                _Action(Icons.quiz_outlined, 'Quiz', tr('{n} quiz disponible(s)', {'n': d.quizzesCount}),
                    () => context.push('/course/${c.id}/quizzes')),
              ],
              if (d.flashcardsCount > 0) ...[
                const SizedBox(height: 10),
                _Action(Icons.style_outlined, 'Flashcards générales',
                    tr('{n} carte(s) à réviser', {'n': d.flashcardsCount}),
                    () => context.push('/flashcards/${c.id}')),
              ],
              const SizedBox(height: 14),
              _CurriculumCard(c.id, repo),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
}

class _CurriculumCard extends StatefulWidget {
  const _CurriculumCard(this.courseId, this.repo);
  final int courseId;
  final CourseRepository repo;
  @override
  State<_CurriculumCard> createState() => _CurriculumCardState();
}

class _CurriculumCardState extends State<_CurriculumCard> {
  late final Future<Loaded<Curriculum>> _cur = widget.repo.curriculum(widget.courseId);
  late final Future<CourseFlashcards?> _fc = _loadFlashcards();

  // Nombre de flashcards par module ; si indisponible, aucun badge (pas d'erreur affichée).
  Future<CourseFlashcards?> _loadFlashcards() async {
    try {
      return (await widget.repo.courseFlashcards(widget.courseId)).value;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<ProgressService>();
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Programme', style: t.textTheme.titleMedium),
          const SizedBox(height: 10),
          FutureBuilder<Loaded<Curriculum>>(
            future: _cur,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) return Text(ApiException.from(snap.error!).message);
              final cur = snap.data!.value;
              final total = cur.allLessons.length;
              final done = cur.allLessons.where((l) => progress.isDone(l.id)).length;
              return FutureBuilder<CourseFlashcards?>(
                future: _fc,
                builder: (context, fsnap) {
                  final fc = fsnap.data;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (total > 0) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                            value: done / total, minHeight: 8, color: EdColors.red, backgroundColor: t.dividerColor),
                      ),
                      const SizedBox(height: 6),
                      Text(tr('{d} / {t} leçon(s) terminée(s) sur cet appareil', {'d': done, 't': total}),
                          style: const TextStyle(fontSize: 12)),
                    ],
                    for (final u in cur.unites) ...[
                      const SizedBox(height: 16),
                      Text(u.titre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      for (final m in u.modules) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Expanded(
                              child: Text(m.titre,
                                  style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
                            ),
                            if (fc != null && fc.countFor(m.id) > 0)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                                icon: const Icon(Icons.style_outlined, size: 18),
                                label: Text(tr('Flashcards ({n})', {'n': fc.countFor(m.id)})),
                                onPressed: () => context.push('/module-flashcards/${m.id}', extra: m.titre),
                              ),
                          ]),
                        ),
                        for (final l in m.lecons)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(progress.isDone(l.id) ? Icons.check_circle_rounded : Icons.play_circle_outline_rounded,
                                color: progress.isDone(l.id) ? EdColors.good : null),
                            title: Text(l.titre),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => context.push('/lesson/${l.id}'),
                          ),
                      ],
                    ],
                    if (total == 0) Text('Aucune leçon active pour ce cours.'),
                  ]);
                },
              );
            },
          ),
        ]),
      ),
    );
  }
}
