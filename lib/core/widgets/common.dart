import 'package:flutter/material.dart';
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
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: t.colorScheme.primary),
          const SizedBox(height: 14),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurface.withValues(alpha: 0.65),
                  height: 1.5)),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]),
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: color ?? Theme.of(context).colorScheme.primary,
        ),
      );
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
                color: t.colorScheme.onSurface.withValues(alpha: 0.65),
                height: 1.5)),
      ],
      const SizedBox(height: 18),
    ]);
  }
}

class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [EdColors.navy, EdColors.navyLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: child,
      );
}

class StatTile extends StatelessWidget {
  const StatTile(this.label, this.value, {super.key, this.hint});
  final String label;
  final String value;
  final String? hint;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: muted)),
          const SizedBox(height: 6),
          Text(value, style: t.textTheme.headlineMedium),
          if (hint != null)
            Text(hint!, style: TextStyle(fontSize: 11, color: muted)),
        ]),
      ),
    );
  }
}

/// Pastille d'état de synchronisation (en ligne / hors ligne / en attente).
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.online, required this.pending});
  final bool online;
  final int pending;
  @override
  Widget build(BuildContext context) {
    final color = !online
        ? EdColors.red
        : pending > 0
            ? const Color(0xFFB7791F)
            : EdColors.good;
    final text = !online
        ? 'Hors ligne'
        : pending > 0
            ? '$pending en attente'
            : 'À jour';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}
