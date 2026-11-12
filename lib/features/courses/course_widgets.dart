import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/i18n/text.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/net_image.dart';
import 'models.dart';

/// Couverture d'un cours : l'image si elle existe, sinon une couverture « typographique » à la
/// couleur de la marque (la première lettre du titre en grand). Légère : aucune image à charger.
class CourseCover extends StatelessWidget {
  const CourseCover(this.course, {super.key, this.aspectRatio = 16 / 9});
  final Course course;
  final double aspectRatio;

  static const _tones = [
    [Color(0xFF060C9C), Color(0xFF0A12E8)],
    [Color(0xFF0B1033), Color(0xFF2A35C9)],
    [Color(0xFF8E1B21), Color(0xFFD22028)],
    [Color(0xFF0A4D8C), Color(0xFF1E88E5)],
    [Color(0xFF1B2470), Color(0xFF5B6CFF)],
  ];

  @override
  Widget build(BuildContext context) {
    final img = course.image;
    if (img != null && img.isNotEmpty) return NetImage(img, aspectRatio: aspectRatio);
    final tone = _tones[course.id.abs() % _tones.length];
    final title = course.titre.trim();
    final letter = title.isEmpty ? 'E' : String.fromCharCode(title.runes.first).toUpperCase();
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: tone, begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Stack(children: [
          Positioned(
            right: -6,
            bottom: -34,
            child: Text(letter,
                style: GoogleFonts.getFont('Bricolage Grotesque',
                    fontSize: 150, fontWeight: FontWeight.w800, height: 1, color: Colors.white.withValues(alpha: 0.16))),
          ),
          Positioned(
            left: 14,
            bottom: 12,
            right: 70,
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont('Bricolage Grotesque',
                    fontSize: 16, fontWeight: FontWeight.w800, height: 1.15, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}

class CourseCard extends StatelessWidget {
  const CourseCard(this.course, {super.key, this.doneLessons});
  final Course course;
  final int? doneLessons;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final access = course.access.hasAccess;
    final price = access
        ? (course.access.source == 'free' ? tr('Gratuit') : tr('Inscrit'))
        : course.prixLabel;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/course/${course.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            CourseCover(course),
            if (course.categorie != null)
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(course.categorie!,
                      style: const TextStyle(
                          color: EdColors.ink, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(course.titre, style: t.textTheme.titleMedium),
              const SizedBox(height: 10),
              Row(children: [
                if (course.niveau != null) ...[_Pill(course.niveau!), const SizedBox(width: 6)],
                if (access) const _Pill('Accès', good: true),
                const Spacer(),
                Icon(Icons.schedule_rounded, size: 14, color: muted),
                const SizedBox(width: 3),
                Text('${course.duree} h', style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 10),
              Text(price,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: access ? EdColors.good : t.colorScheme.primary)),
              if (doneLessons != null && doneLessons! > 0) ...[
                const SizedBox(height: 6),
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
      width: 260,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/course/${course.id}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CourseCover(course, aspectRatio: 16 / 10),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.titre,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  '${course.duree} h · ${course.prixLabel}',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800, color: t.colorScheme.primary),
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
