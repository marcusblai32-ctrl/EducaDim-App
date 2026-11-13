import 'package:flutter/material.dart' hide Text;
import '../../core/i18n/text.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/security/offline_access.dart';
import '../../core/widgets/common.dart';
import '../courses/offline_course_service.dart';
import 'download_service.dart';

String formatBytes(int b) {
  if (b < 1024) return '$b o';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} Ko';
  return '${(b / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DownloadService>().load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<DownloadService>();
    final oc = context.watch<OfflineCourseService>();
    final ac = context.watch<OfflineAccess>();
    return Scaffold(
      appBar: AppBar(title: const Text('Téléchargements')),
      body: (s.items.isEmpty && oc.courses.isEmpty)
          ? const EmptyState(
              icon: Icons.download_for_offline_outlined,
              title: 'Aucun contenu téléchargé',
              message:
                  'Ouvrez un cours auquel vous avez accès et touchez « Télécharger '
                  'le cours » pour le lire sans connexion.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                HeroCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Eyebrow('Stockage local', color: Color(0xFFB9C2FF)),
                    const SizedBox(height: 6),
                    Text(tr('{c} cours · {f} fichier(s) · {b}', {'c': oc.courses.length, 'f': s.items.length, 'b': formatBytes(s.totalBytes)}),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(height: 14),
                if (oc.courses.isNotEmpty) ...[
                  const Text('Cours hors ligne',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final c in oc.courses)
                    Card(
                      child: ListTile(
                        leading: Icon(ac.isLocked(c.courseId) ? Icons.lock_outline : Icons.menu_book_outlined),
                        title: Text(c.title),
                        subtitle: Text(ac.isLocked(c.courseId)
                            ? tr('Accès expiré. Renouvelez votre abonnement dans les 3 jours, sinon ce cours sera supprimé de cet appareil.')
                            : c.skipped > 0
                            ? tr('{n} leçon(s) lisible(s) hors ligne · {k} verrouillée(s) par un quiz', {'n': c.lessons, 'k': c.skipped})
                            : tr('{n} leçon(s) lisible(s) hors ligne', {'n': c.lessons})),
                        onTap: () => context.push('/course/${c.courseId}'),
                        trailing: IconButton(
                          tooltip: tr('Supprimer'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => oc.remove(c.courseId),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                ],
                if (s.items.isNotEmpty)
                  const Text('Fichiers', style: TextStyle(fontWeight: FontWeight.w800)),
                for (final d in s.items)
                  Card(
                    child: ListTile(
                      leading: Icon(d.courseId != null && ac.isLocked(d.courseId!) ? Icons.lock_outline : Icons.offline_pin_outlined),
                      title: Text(d.title),
                      subtitle: Text(tr('{b} · Protégé, lisible seulement dans EducaDim', {'b': formatBytes(d.bytes)})),
                      onTap: () => context.push('/secure-pdf/${d.id}', extra: d.title),
                      trailing: IconButton(
                        tooltip: tr('Supprimer'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => s.remove(d.id),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
