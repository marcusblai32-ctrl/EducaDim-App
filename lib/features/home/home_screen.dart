import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/i18n/text.dart';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Les requêtes sont lancées une seule fois (pas à chaque reconstruction) : économie de données.
  late final Future<Loaded<CoursePage>> _catalog = context.read<CourseRepository>().catalog();
  late final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  Future<void> _refresh() async {
    await context.read<CourseRepository>().catalog();
    if (mounted) context.read<SyncService>().flush();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final sync = context.watch<SyncService>();
    final progress = context.watch<ProgressService>();
    final offline = context.watch<OfflineCourseService>();
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.65);
    final name = auth.fullName.isNotEmpty ? auth.fullName : auth.firstName;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 100), children: [
        // ---- Salutation ----
        Row(children: [
          InitialsAvatar(name.isEmpty ? '?' : name, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bonjour,', style: TextStyle(color: muted, fontWeight: FontWeight.w600)),
              Text(auth.firstName.isEmpty ? tr('Apprenant') : auth.firstName,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.headlineMedium),
            ]),
          ),
        ]),
        const SizedBox(height: 18),

        // ---- Reprise ----
        FutureBuilder<SharedPreferences>(
          future: _prefs,
          builder: (context, snap) {
            final parts = snap.data?.getString(kLastLessonKey)?.split('\u0001');
            final last = (parts != null && parts.length == 3) ? parts : null;
            return HeroCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Eyebrow(last != null ? 'Reprendre où vous en étiez' : 'Votre espace d’apprentissage',
                    color: const Color(0xFFB9C2FF)),
                const SizedBox(height: 10),
                Text(last != null ? last[2] : tr('Prêt à apprendre ?'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 6),
                Text(tr('{n} leçon(s) terminée(s)', {'n': progress.totalCompleted}),
                    style: const TextStyle(color: Color(0xFFDDE2FF))),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: EdColors.blueDeep),
                  onPressed: () =>
                      last != null ? context.push('/lesson/${last[1]}') : context.go('/courses'),
                  child: Text(last != null ? 'Continuer la leçon' : 'Voir mes cours'),
                ),
              ]),
            );
          },
        ),
        const SizedBox(height: 18),

        // ---- Accès rapides ----
        Row(children: [
          _Quick(Icons.explore_rounded, 'Explorer', () => context.go('/explore')),
          _Quick(Icons.insights_rounded, 'Progression', () => context.push('/progress')),
          _Quick(Icons.workspace_premium_rounded, 'Certificats', () => context.push('/certificates')),
          _Quick(Icons.download_for_offline_rounded, 'Hors ligne', () => context.push('/downloads')),
        ]),
        const SizedBox(height: 16),

        // ---- Chiffres ----
        Row(children: [
          Expanded(
              child: StatTile('Leçons terminées', '${progress.totalCompleted}',
                  icon: Icons.check_circle_outline_rounded)),
          const SizedBox(width: 10),
          Expanded(
              child: StatTile('Cours hors ligne', '${offline.courses.length}',
                  icon: Icons.offline_pin_outlined)),
          const SizedBox(width: 10),
          Expanded(
              child: StatTile('En attente d’envoi', '${sync.pending}', icon: Icons.schedule_send_outlined)),
        ]),
        const SizedBox(height: 10),

        // ---- Recommandations ----
        SectionTitle('Recommandé pour vous', actionLabel: tr('Tout voir'), onAction: () => context.go('/explore')),
        FutureBuilder<Loaded<CoursePage>>(
          future: _catalog,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 220, child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Catalogue indisponible pour le moment.', style: TextStyle(color: muted)),
              );
            }
            final list = snap.data!.value.results.where((c) => !c.access.hasAccess).take(6).toList();
            if (list.isEmpty) {
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucune nouvelle recommandation.', style: TextStyle(color: muted)));
            }
            return SizedBox(
              height: 252,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => CourseCardCompact(list[i]),
              ),
            );
          },
        ),
        if (sync.note != null) ...[
          const SizedBox(height: 14),
          Card(
            color: EdColors.warn.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: EdColors.warn),
                const SizedBox(width: 10),
                Expanded(child: Text(sync.note!, style: const TextStyle(fontSize: 12.5))),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: t.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: t.colorScheme.primary),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
