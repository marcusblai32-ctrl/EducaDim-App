import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/common.dart';
import '../downloads/download_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final dl = context.watch<DownloadService>();
    final t = Theme.of(context);
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        HeroCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('Votre espace d’apprentissage', color: Color(0xFF83DCE5)),
            const SizedBox(height: 8),
            const Text('Prêt à apprendre ?',
                style: TextStyle(
                    color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Reprenez votre parcours là où vous l’avez laissé.',
                style: TextStyle(color: Color(0xFFD3E2E9), height: 1.5)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/courses'),
              child: const Text('Reprendre mes cours  →'),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: StatTile('Hors ligne', '${dl.items.length}', hint: 'contenu(s)')),
          const SizedBox(width: 8),
          Expanded(
              child: StatTile('En attente', '${sync.pending}', hint: 'à synchroniser')),
          const SizedBox(width: 8),
          Expanded(
              child: StatTile('Réseau', sync.online ? 'OK' : 'Off', hint: 'connexion')),
        ]),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: const Icon(Icons.sync_rounded, color: EdColors.blue),
            title: const Text('Synchronisation'),
            subtitle: Text(sync.note ??
                (sync.pending == 0
                    ? 'Tout est synchronisé.'
                    : 'Des données locales attendent d’être envoyées.')),
            trailing: SyncBadge(online: sync.online, pending: sync.pending),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Mes téléchargements'),
            subtitle: Text('${dl.items.length} contenu(s) disponible(s) hors ligne'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/downloads'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Recommandations, progression et dernier cours seront alimentés par '
          'l’API Django une fois les endpoints confirmés.',
          style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      ]),
    );
  }
}
