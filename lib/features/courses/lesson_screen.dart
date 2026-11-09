import 'package:flutter/material.dart' hide Text;
import '../../core/i18n/text.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/controlled_video.dart';
import '../../core/widgets/net_image.dart';
import '../../core/widgets/common.dart';
import '../downloads/download_service.dart';
import 'course_repository.dart';
import 'course_widgets.dart';
import 'models.dart';
import 'progress_service.dart';

const kLastLessonKey = 'last_lesson'; // "courseId:lessonId:titre"

class LessonScreen extends StatefulWidget {
  const LessonScreen(this.lessonId, {super.key});
  final int lessonId;
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late Future<Loaded<Lesson>> _f = _load();

  Future<Loaded<Lesson>> _load() async {
    final r = await context.read<CourseRepository>().lesson(widget.lessonId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLastLessonKey,
        '${r.value.courseId}\u0001${r.value.id}\u0001${r.value.titre}');
    return r;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Leçon')),
        body: FutureBuilder<Loaded<Lesson>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final err = snap.error;
            if (err is LessonQuizRequired) {
              return EmptyState(
                icon: Icons.quiz_outlined,
                title: 'Quiz à réussir d’abord',
                message: err.message,
                action: FilledButton(
                  onPressed: () => err.quizIds.isNotEmpty
                      ? context.push('/quiz/${err.quizIds.first}')
                      : launchUrl(Uri.parse(ApiConfig.siteUrl),
                          mode: LaunchMode.externalApplication),
                  child: Text(err.quizIds.isNotEmpty ? 'Passer le quiz' : 'Ouvrir le site'),
                ),
              );
            }
            if (err != null) {
              return EmptyState(
                icon: err is CourseAccessRequired ? Icons.lock_outline : Icons.cloud_off_rounded,
                title: err is CourseAccessRequired ? 'Accès requis' : 'Chargement impossible',
                message: ApiException.from(err).message,
                action: OutlinedButton(
                    onPressed: () => setState(() => _f = _load()),
                    child: const Text('Réessayer')),
              );
            }
            final r = snap.data!;
            return _LessonBody(r.value, r.fromCache);
          },
        ),
      );
}

class _LessonBody extends StatelessWidget {
  const _LessonBody(this.l, this.fromCache);
  final Lesson l;
  final bool fromCache;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final progress = context.watch<ProgressService>();
    final done = progress.isDone(l.id);
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (fromCache) const OfflineBanner(),
      Text(l.titre, style: t.textTheme.headlineMedium),
      if (l.description.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(l.description, style: t.textTheme.bodyMedium?.copyWith(height: 1.5)),
      ],
      if (l.contenu.trim().isNotEmpty) ...[
        const SizedBox(height: 14),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(l.contenu, style: const TextStyle(height: 1.6)))),
      ],
      for (final s in l.sections) ...[
        const SizedBox(height: 18),
        Eyebrow(s.type),
        const SizedBox(height: 4),
        Text(s.titre, style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final c in s.contenus) _ContentTile(c),
      ],
      if (l.sections.isEmpty && l.contenu.trim().isEmpty)
        const SizedBox(
            height: 220,
            child: EmptyState(
                icon: Icons.article_outlined,
                title: 'Leçon sans contenu',
                message: 'Aucun contenu n’a encore été publié pour cette leçon.')),
      const SizedBox(height: 22),
      FilledButton.icon(
        icon: Icon(done ? Icons.check_circle : Icons.check),
        label: Text(done ? 'Leçon terminée' : 'Marquer comme terminée'),
        style: done ? FilledButton.styleFrom(backgroundColor: EdColors.good) : null,
        onPressed: done
            ? null
            : () async {
                await progress.complete(l.id, l.courseId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, SnackBar(
                      content: Text(tr('Progression enregistrée. Synchronisation automatique dès que possible.'))));
                }
              },
      ),
      const SizedBox(height: 8),
      OutlinedButton(
          onPressed: () => context.pop(), child: const Text('← Retour au programme')),
    ]);
  }
}

class _ContentTile extends StatelessWidget {
  const _ContentTile(this.c);
  final LessonContent c;

  static const _labels = {
    'video': 'Vidéo',
    'audio': 'Audio',
    'pdf': 'Document PDF',
    'fichier': 'Fichier',
    'lien': 'Lien externe',
    'image': 'Image',
  };
  static const _icons = {
    'video': Icons.play_circle_fill,
    'audio': Icons.headphones,
    'pdf': Icons.picture_as_pdf_outlined,
    'fichier': Icons.attach_file,
    'lien': Icons.open_in_new,
  };

  @override
  Widget build(BuildContext context) {
    if (c.type == 'texte') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((c.titre ?? '').isNotEmpty)
            Text(c.titre!, style: const TextStyle(fontWeight: FontWeight.w800)),
          SelectableText(c.texte ?? '', style: const TextStyle(height: 1.65)),
        ]),
      );
    }
    final url = c.mainUrl;
    if (c.type == 'image' && url != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: NetImage(url, aspectRatio: null, fit: BoxFit.fitWidth),
        ),
      );
    }
    if (c.type == 'video' && url != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((c.titre ?? '').isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(c.titre!, style: const TextStyle(fontWeight: FontWeight.w800))),
          ControlledVideo(url: url, title: c.titre),
        ]),
      );
    }
    final downloadable = c.type == 'pdf' || c.type == 'audio' || c.type == 'fichier';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: Icon(_icons[c.type] ?? Icons.insert_drive_file_outlined),
        title: Text((c.titre ?? '').isNotEmpty ? c.titre! : (_labels[c.type] ?? 'Ressource')),
        subtitle: Text(_labels[c.type] ?? c.type),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (downloadable && url != null)
            IconButton(
              tooltip: tr('Télécharger'),
              icon: const Icon(Icons.download_outlined),
              onPressed: () async {
                final msg = ScaffoldMessenger.of(context);
                try {
                  await context
                      .read<DownloadService>()
                      .download('content-${c.id}', c.titre ?? _labels[c.type]!, url);
                  msg.showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, const SnackBar(content: Text('Téléchargé pour le hors ligne.')));
                } catch (_) {
                  msg.showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, 
                      const SnackBar(content: Text('Téléchargement impossible. Vérifiez votre connexion.')));
                }
              },
            ),
          IconButton(
            tooltip: tr('Ouvrir'),
            icon: const Icon(Icons.open_in_new),
            onPressed: url == null
                ? null
                : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        ]),
      ),
    );
  }
}
