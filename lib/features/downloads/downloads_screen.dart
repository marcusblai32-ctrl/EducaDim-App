import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
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
                    const Eyebrow('Stockage local', color: Color(0xFF83DCE5)),
                    const SizedBox(height: 6),
                    Text('${oc.courses.length} cours · ${s.items.length} fichier(s) · ${formatBytes(s.totalBytes)}',
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
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(c.title),
                        subtitle: Text(
                            '${c.lessons} leçon(s) lisible(s) hors ligne'
                            '${c.skipped > 0 ? ' · ${c.skipped} verrouillée(s) par un quiz' : ''}'),
                        onTap: () => context.push('/course/${c.courseId}'),
                        trailing: IconButton(
                          tooltip: 'Supprimer',
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
                      leading: const Icon(Icons.offline_pin_outlined),
                      title: Text(d.title),
                      subtitle: Text('${formatBytes(d.bytes)} · Disponible hors ligne'),
                      trailing: IconButton(
                        tooltip: 'Supprimer',
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
