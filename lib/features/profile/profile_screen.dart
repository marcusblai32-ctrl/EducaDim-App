import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/common.dart';
import '../admin/admin_repository.dart';
import '../auth/auth_controller.dart';
import '../review/review_service.dart';
import '../review/review_sheet.dart';
import '../../core/alerts/alert_service.dart';
import '../study/study_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final sync = context.watch<SyncService>();
    final auth = context.watch<AuthController>();
    final review = context.watch<ReviewService>();
    final study = context.watch<StudyService>();
    final isAdmin = context.watch<AdminAccess>().canManage;
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final name = auth.fullName.isEmpty ? tr('Utilisateur') : auth.fullName;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
      // ---- Identité ----
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            InitialsAvatar(name, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(auth.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted)),
                if (isAdmin || ((auth.user?['active_subscriptions'] as List?)?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, children: [
                    if (isAdmin) _Tag('Administration', EdColors.red),
                    if ((auth.user?['active_subscriptions'] as List?)?.isNotEmpty ?? false)
                      _Tag('Abonnement actif', EdColors.good),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 14),

      if (isAdmin) ...[
        Card(
          color: EdColors.red.withValues(alpha: 0.08),
          child: ListTile(
            leading: const Icon(Icons.admin_panel_settings_rounded, color: EdColors.red),
            title: const Text('Administration', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Ajouter, modifier ou supprimer cours, leçons et quiz'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/admin'),
          ),
        ),
        const SizedBox(height: 14),
      ],

      const SectionTitle('Mon apprentissage'),
      _Group([
        _Item(Icons.insights_rounded, 'Ma progression', () => context.push('/progress')),
        _Item(Icons.local_fire_department_rounded, 'Mon rythme d’étude', () => context.push('/study/plan'),
            subtitle: study.hasPlan ? tr('{n} jour(s) par semaine', {'n': study.weekdays.length}) : null),
        _Item(Icons.leaderboard_rounded, 'Classement des séries', () => context.push('/leaderboard')),
        _Item(Icons.emoji_events_rounded, 'Classement par points', () => context.push('/ranking')),
        _Item(Icons.military_tech_rounded, 'Mes badges', () => context.push('/badges')),
        _Item(Icons.piano_rounded, 'Pratique musicale (PPI)', () => context.push('/ppi-progress')),
        _Item(Icons.workspace_premium_rounded, 'Mes certificats', () => context.push('/certificates')),
        _Item(Icons.download_for_offline_rounded, 'Téléchargements', () => context.push('/downloads')),
        _Item(Icons.forum_rounded, 'Discussions', () => context.push('/chat')),
      ]),
      const SizedBox(height: 14),

      const SectionTitle('Préférences'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Langue', style: t.textTheme.titleSmall),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'fr', label: Text('Français')),
                  ButtonSegment(value: 'ht', label: Text('Kreyòl')),
                ],
                selected: {Lang.instance.code},
                onSelectionChanged: (s) => Lang.instance.set(s.first),
              ),
            ),
            const SizedBox(height: 18),
            Text('Apparence', style: t.textTheme.titleSmall),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Clair')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Sombre')),
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android_rounded), label: Text('Auto')),
                ],
                selected: {theme.mode},
                onSelectionChanged: (s) => theme.setMode(s.first),
              ),
            ),
            const SizedBox(height: 8),
            const _SoundSwitch(),
          ]),
        ),
      ),
      const SizedBox(height: 14),

      const SectionTitle('Application'),
      _Group([
        if (review.enabled)
          _Item(
            review.answered ? Icons.star_rounded : Icons.star_outline_rounded,
            review.answered ? 'Modifier mon avis' : 'Donner mon avis',
            () => showReviewSheet(context),
            trailing: review.answered && review.stars != null
                ? Text('${review.stars}/5',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFF5A623)))
                : null,
          ),
        _Item(
          Icons.sync_rounded,
          'Synchroniser maintenant',
          sync.flush,
          subtitle: tr('{n} élément(s) en attente', {'n': sync.pending}),
          trailing: sync.syncing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
        ),
      ]),
      const SizedBox(height: 22),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
            foregroundColor: EdColors.red, side: BorderSide(color: EdColors.red.withValues(alpha: 0.4))),
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Se déconnecter'),
        onPressed: () => context.read<AuthController>().logout(),
      ),
    ]);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(30)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      );
}

class _Item {
  _Item(this.icon, this.title, this.onTap, {this.subtitle, this.trailing});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? subtitle;
  final Widget? trailing;
}

class _Group extends StatelessWidget {
  const _Group(this.items);
  final List<_Item> items;
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            ListTile(
              leading: Icon(items[i].icon),
              title: Text(items[i].title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: items[i].subtitle == null ? null : Text(items[i].subtitle!),
              trailing: items[i].trailing ?? const Icon(Icons.chevron_right_rounded),
              onTap: items[i].onTap,
            ),
            if (i < items.length - 1) const Divider(indent: 56),
          ],
        ]),
      );
}


class _SoundSwitch extends StatefulWidget {
  const _SoundSwitch();
  @override
  State<_SoundSwitch> createState() => _SoundSwitchState();
}

class _SoundSwitchState extends State<_SoundSwitch> {
  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Sons des notifications et rappels', style: TextStyle(fontWeight: FontWeight.w700)),
        value: AlertService.instance.soundEnabled,
        onChanged: (v) async {
          await AlertService.instance.setSound(v);
          if (mounted) setState(() {});
        },
      );
}
