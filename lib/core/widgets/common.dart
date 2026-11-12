import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import '../theme/colors.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: t.colorScheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 38, color: t.colorScheme.primary),
          ),
          const SizedBox(height: 20),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurface.withValues(alpha: 0.65), height: 1.5)),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ]),
      ),
    );
  }
}

/// Sur-titre : un petit trait rouge (le « trait de correction » du professeur) + texte en casse normale.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 16,
        height: 3,
        decoration: BoxDecoration(color: EdColors.red, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          tr(text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c),
        ),
      ),
    ]);
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader(this.kicker, this.title, {super.key, this.subtitle});
  final String kicker;
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Eyebrow(kicker),
      const SizedBox(height: 6),
      Text(title, style: t.textTheme.headlineLarge),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(subtitle!,
            style: t.textTheme.bodyMedium?.copyWith(
                color: t.colorScheme.onSurface.withValues(alpha: 0.65), height: 1.5)),
      ],
      const SizedBox(height: 18),
    ]);
  }
}

/// Titre de section avec action facultative (« Voir tout »).
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ]),
      );
}

class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(EdRadius.hero),
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: EdColors.hero),
          child: Stack(children: [
            // Anneaux concentriques : rappel de l'anneau de progression, motif de la marque.
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _RingsPainter()))),
            Padding(padding: const EdgeInsets.all(22), child: child),
          ]),
        ),
      );
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.92, size.height * 0.08);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 1; i <= 5; i++) {
      p.color = Colors.white.withValues(alpha: 0.13 - i * 0.018);
      canvas.drawCircle(center, 34.0 * i + 20, p);
    }
    canvas.drawCircle(
        Offset(size.width * 0.06, size.height * 1.02), 54, Paint()..color = EdColors.red.withValues(alpha: 0.22));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Anneau de progression (0 → 1) avec un contenu au centre. Aucune animation (appareils modestes).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 92,
    this.stroke = 9,
    this.color = Colors.white,
    this.track,
    this.child,
  });
  final double value;
  final double size;
  final double stroke;
  final Color color;
  final Color? track;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value.clamp(0.0, 1.0), stroke, color, track ?? color.withValues(alpha: 0.22)),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.stroke, this.color, this.track);
  final double value;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    base.color = track;
    canvas.drawArc(arc, 0, math.pi * 2, false, base);
    if (value > 0) {
      base.color = color;
      canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * value, false, base);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

/// Limite la largeur du contenu sur grand écran (tablette, ordinateur) et le centre.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = EdLayout.maxContent});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

class StatTile extends StatelessWidget {
  const StatTile(this.label, this.value, {super.key, this.hint, this.icon});
  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: t.colorScheme.primary),
            const SizedBox(height: 8),
          ],
          Text(value, style: t.textTheme.headlineMedium?.copyWith(fontSize: 26)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 2,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: muted)),
          if (hint != null) Text(hint!, style: TextStyle(fontSize: 10.5, color: muted)),
        ]),
      ),
    );
  }
}

/// Point vert « en ligne » (rien n'est affiché quand on n'est pas connecté).
class OnlineDot extends StatelessWidget {
  const OnlineDot({super.key, this.size = 11});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: EdColors.good,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
        ),
      );
}

/// Indicateur de connexion : un petit point vert quand l'appareil est connecté, rien sinon.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.online, required this.pending});
  final bool online;
  final int pending;
  @override
  Widget build(BuildContext context) =>
      online ? Tooltip(message: tr('En ligne'), child: const OnlineDot()) : const SizedBox.shrink();
}

/// Avatar rond avec initiales.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 56, this.online = false});
  final String name;
  final double size;
  final bool online;
  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: EdColors.hero, shape: BoxShape.circle),
      child: Text(initials,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
    if (!online) return avatar;
    return Stack(clipBehavior: Clip.none, children: [
      avatar,
      Positioned(right: -1, bottom: -1, child: OnlineDot(size: size * 0.28)),
    ]);
  }
}
