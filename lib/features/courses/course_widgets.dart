import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
import '../../core/i18n/text.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/net_image.dart';
import 'models.dart';

class CourseCard extends StatelessWidget {
  const CourseCard(this.course, {super.key, this.doneLessons});
  final Course course;
  final int? doneLessons;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/course/${course.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // L'image occupe toute la largeur du card (16:9, recadrée sans déformation).
          Stack(children: [
            NetImage(course.image),
            if (course.categorie != null)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(course.categorie!,
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, children: [
                if (course.niveau != null) _Pill(course.niveau!),
                if (course.access.hasAccess) const _Pill('Accès', good: true),
              ]),
              const SizedBox(height: 8),
              Text(course.titre, style: t.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '${course.duree} h · ${course.access.hasAccess ? (course.access.source == 'free' ? tr('Gratuit') : tr('Inscrit')) : course.prixLabel}',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              if (doneLessons != null && doneLessons! > 0) ...[
                const SizedBox(height: 8),
                Text(tr('{n} leçon(s) terminée(s)', {'n': doneLessons}),
                    style: const TextStyle(
                        fontSize: 12, color: EdColors.good, fontWeight: FontWeight.w700)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Carte horizontale compacte (carrousel de recommandations).
class CourseCardCompact extends StatelessWidget {
  const CourseCardCompact(this.course, {super.key});
  final Course course;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      width: 250,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/course/${course.id}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NetImage(course.image, aspectRatio: 16 / 10),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.titre,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  '${course.duree} h · ${course.prixLabel}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t.colorScheme.primary),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.good = false});
  final String text;
  final bool good;
  @override
  Widget build(BuildContext context) {
    final c = good ? EdColors.good : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(30)),
      child: Text(text,
          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: EdColors.warn.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Hors ligne : données enregistrées lors de votre dernière connexion.',
          style: TextStyle(fontSize: 12, color: EdColors.warn),
        ),
      );
}
