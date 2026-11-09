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

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        tr(text).toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.3,
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
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: EdColors.hero),
          child: Stack(children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
              ),
            ),
            Positioned(
              right: 30,
              bottom: -50,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: EdColors.red.withValues(alpha: 0.22)),
              ),
            ),
            Padding(padding: const EdgeInsets.all(22), child: child),
          ]),
        ),
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
          Text(value, style: t.textTheme.headlineMedium),
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
