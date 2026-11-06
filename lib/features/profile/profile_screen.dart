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
    final auth = context.watch<AuthController>();
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const PageHeader('Espace personnel', 'Mon profil'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(auth.fullName.isEmpty ? 'Utilisateur' : auth.fullName,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(auth.email),
              if (auth.user?['user_id'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Identifiant : ${auth.user!['user_id']}'),
                ),
              if ((auth.user?['active_subscriptions'] as List?)?.isNotEmpty ?? false)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Abonnement actif', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
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
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Ma progression'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/progress'),
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
