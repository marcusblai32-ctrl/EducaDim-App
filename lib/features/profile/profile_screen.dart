import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_controller.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final sync = context.watch<SyncService>();
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const PageHeader('Espace personnel', 'Mon profil',
            subtitle: 'Les informations de compte seront chargées depuis le '
                'serveur dès que l’endpoint de profil sera confirmé.'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Apparence', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
                  ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                ],
                selected: {theme.mode},
                onSelectionChanged: (s) => theme.setMode(s.first),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: const Text('Synchroniser maintenant'),
            subtitle: Text('${sync.pending} élément(s) en attente'),
            trailing: sync.syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: sync.flush,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Téléchargements'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/downloads'),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Serveur'),
            subtitle: Text(ApiConfig.baseUrl),
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Se déconnecter'),
          onPressed: () => context.read<AuthController>().logout(),
        ),
      ]),
    );
  }
}
