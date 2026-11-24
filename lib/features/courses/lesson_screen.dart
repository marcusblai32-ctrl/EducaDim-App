import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import '../../core/i18n/text.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/audio/sfx.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/audio_player.dart';
import '../../core/widgets/controlled_video.dart';
import '../../core/widgets/image_viewer.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/text_size.dart';
import '../../core/security/offline_access.dart';
import '../downloads/download_service.dart';
import 'course_repository.dart';
import 'course_widgets.dart';
import 'models.dart';
import 'online_pdf_screen.dart';
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
  Widget build(BuildContext context) => TextSizeScope(child: Scaffold(
        appBar: AppBar(title: const Text('Leçon'), actions: textSizeActions()),
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
      ));
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
      if (l.sections.isNotEmpty) const SizedBox(height: 16),
      for (final s in l.sections) _SectionTile(s, l.courseId),
      if (l.sections.isEmpty && l.contenu.trim().isEmpty)
        const SizedBox(
            height: 220,
            child: EmptyState(
                icon: Icons.article_outlined,
                title: 'Leçon sans contenu',
                message: 'Aucun contenu n’a encore été publié pour cette leçon.')),
      const SizedBox(height: 22),
      if (l.ppi != null && !done) _PpiRequirementCard(l.ppi!),
      FilledButton.icon(
        icon: Icon(done ? Icons.check_circle : Icons.check),
        label: Text(done
            ? 'Leçon terminée'
            : (l.ppi != null && !l.ppi!.met ? 'Terminez d’abord les exercices PPI' : 'Marquer comme terminée')),
        style: done ? FilledButton.styleFrom(backgroundColor: EdColors.good) : null,
        onPressed: done || (l.ppi != null && !l.ppi!.met)
            ? null
            : () async {
                await progress.complete(l.id, l.courseId);
                unawaited(Sfx.complete());
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

/// Section dépliable sur place (sans animation) : un clic ouvre / referme les contenus.
class _SectionTile extends StatefulWidget {
  const _SectionTile(this.s, this.courseId);
  final LessonSection s;
  final int courseId;
  @override
  State<_SectionTile> createState() => _SectionTileState();
}

class _SectionTileState extends State<_SectionTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = widget.s;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (s.type.isNotEmpty) Eyebrow(s.type),
                Text(s.titre, style: t.textTheme.titleMedium),
              ])),
              Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
            ]),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: s.contenus.isEmpty
                ? Text(tr('Aucun contenu dans cette section.'))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final c in s.contenus) _ContentTile(c, widget.courseId),
                  ]),
          ),
      ]),
    );
  }
}

class _ContentTile extends StatelessWidget {
  const _ContentTile(this.c, this.courseId);
  final LessonContent c;
  final int courseId;

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
    final kind = c.kind; // décidé par le serveur d'après le vrai fichier : n'importe quel fichier reste lisible
    if (kind == 'image' && url != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ZoomableNetImage(url, title: c.titre),
      );
    }
    if (kind == 'video' && url != null) {
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
    if (kind == 'audio' && url != null) {
      return AudioPlayerTile(url: url, title: c.titre, mime: null);
    }
    if (kind == 'pdf' && url != null) {
      // Lecture DANS l'application seulement : pas de téléchargement, pas d'ouverture dans une autre application.
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text((c.titre ?? '').isNotEmpty ? c.titre! : 'Document PDF'),
          subtitle: Text(tr('Lire le document')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => OnlinePdfScreen(url, title: c.titre))),
        ),
      );
    }
    if (kind == 'link' && url != null) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: ListTile(
          leading: const Icon(Icons.open_in_new),
          title: Text((c.titre ?? '').isNotEmpty ? c.titre! : 'Lien externe'),
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
      );
    }
    // Autre type de fichier (Word, Excel, zip…) : l'application ne peut pas l'afficher sans le rendre téléchargeable.
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: const Icon(Icons.lock_outline),
        title: Text((c.titre ?? '').isNotEmpty ? c.titre! : 'Fichier'),
        subtitle: Text(tr('Ce fichier n’est pas lisible dans l’application.')),
      ),
    );
  }
}

/// « Pratique PPI » : combien d'exercices il reste à finir + bouton qui ouvre l'application PPI.
class _PpiRequirementCard extends StatelessWidget {
  const _PpiRequirementCard(this.r);
  final PpiRequirement r;

  @override
  Widget build(BuildContext context) {
    final left = (r.required - r.done).clamp(0, r.required);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(r.met ? Icons.check_circle : Icons.piano_rounded, color: r.met ? EdColors.good : EdColors.blue),
            const SizedBox(width: 8),
            Expanded(
                child: Text(tr('Pratique PPI : {d} / {n} exercices finis', {'d': r.done, 'n': r.required}),
                    style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: r.required == 0 ? 1 : r.done / r.required, minHeight: 8),
          const SizedBox(height: 8),
          Text(r.met
              ? tr('Bravo ! Tu peux terminer la leçon.')
              : tr('Il te reste {n} exercice(s) à finir dans PPI pour terminer cette leçon.', {'n': left}) +
                  (r.minAccuracy > 0 ? ' ' + tr('Précision minimale : {p} %.', {'p': r.minAccuracy}) : '')),
          if (!r.met) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.piano_rounded),
              label: Text(tr('Ouvrir PPI')),
              onPressed: () async {
                final ok = await launchUrl(Uri.parse('ppi://app/'), mode: LaunchMode.externalApplication)
                    .catchError((_) => false);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr('Installe ou ouvre l’application PPI pour pratiquer.'))));
                }
              },
            ),
          ],
        ]),
      ),
    );
  }
}
