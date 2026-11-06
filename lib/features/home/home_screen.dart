import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_controller.dart';
import '../courses/course_repository.dart';
import '../courses/course_widgets.dart';
import '../courses/lesson_screen.dart' show kLastLessonKey;
import '../courses/models.dart';
import '../courses/offline_course_service.dart';
import '../courses/progress_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final sync = context.watch<SyncService>();
    final progress = context.watch<ProgressService>();
    final offline = context.watch<OfflineCourseService>();
    final repo = context.read<CourseRepository>();
    final t = Theme.of(context);
    final name = auth.firstName.isEmpty ? '' : ' ${auth.firstName}';

    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        HeroCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('Votre espace d’apprentissage', color: Color(0xFF83DCE5)),
            const SizedBox(height: 8),
            Text('Bonjour$name, prêt à apprendre ?',
                style: const TextStyle(
                    color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Reprenez votre parcours là où vous l’avez laissé.',
                style: TextStyle(color: Color(0xFFD3E2E9), height: 1.5)),
            const SizedBox(height: 16),
            FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (context, snap) {
                final parts = snap.data?.getString(kLastLessonKey)?.split('\u0001');
                final raw = (parts != null && parts.length == 3) ? parts : null;
                return FilledButton(
                  onPressed: () => raw != null
                      ? context.push('/lesson/${raw[1]}')
                      : context.go('/courses'),
                  child: Text(raw != null ? 'Reprendre : ${raw[2]}' : 'Voir mes cours  →',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: StatTile('Leçons terminées', '${progress.totalCompleted}',
                  hint: 'sur cet appareil')),
          const SizedBox(width: 8),
          Expanded(
              child: StatTile('Hors ligne', '${offline.courses.length}', hint: 'cours')),
          const SizedBox(width: 8),
          Expanded(
              child: StatTile('À envoyer', '${sync.pending}', hint: 'en attente')),
        ]),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Recommandations', style: t.textTheme.titleLarge),
          TextButton(onPressed: () => context.go('/explore'), child: const Text('Explorer →')),
        ]),
        FutureBuilder<Loaded<CoursePage>>(
          future: repo.catalog(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Catalogue indisponible pour le moment.'),
              );
            }
            final list = snap.data!.value.results
                .where((c) => !c.access.hasAccess)
                .take(3)
                .toList();
            if (list.isEmpty) {
              return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucune nouvelle recommandation.'));
            }
            return Column(children: [
              if (snap.data!.fromCache) const OfflineBanner(),
              for (final c in list) ...[CourseCard(c), const SizedBox(height: 14)],
            ]);
          },
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.sync_rounded, color: EdColors.blue),
            title: const Text('Synchronisation'),
            subtitle: Text(sync.note ??
                (sync.pending == 0
                    ? 'Tout est synchronisé.'
                    : 'Des données locales attendent d’être envoyées.')),
            trailing: SyncBadge(online: sync.online, pending: sync.pending),
          ),
        ),
      ]),
    );
  }
}
