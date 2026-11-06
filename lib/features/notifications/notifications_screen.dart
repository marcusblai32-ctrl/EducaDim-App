import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/common.dart';
import '../courses/course_widgets.dart';
import '../courses/models.dart' show formatDate;
import 'notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<NotificationService>().refresh());
  }

  static IconData _icon(String t) => switch (t) {
        'lecon' => Icons.menu_book_outlined,
        'quiz' => Icons.quiz_outlined,
        'badge' => Icons.military_tech_outlined,
        'reunion' => Icons.event_outlined,
        'message' => Icons.chat_bubble_outline,
        _ => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<NotificationService>();
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (svc.unread > 0)
            TextButton(onPressed: svc.markAllRead, child: const Text('Tout lire')),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Builder(builder: (_) {
            if (svc.loading && svc.items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (svc.items.isEmpty) {
              return RefreshIndicator(
                onRefresh: svc.refresh,
                child: ListView(children: [
                  SizedBox(
                    height: 380,
                    child: EmptyState(
                      icon: svc.error == null
                          ? Icons.notifications_none_rounded
                          : Icons.cloud_off_rounded,
                      title: svc.error == null ? 'Aucune notification' : 'Chargement impossible',
                      message: svc.error ?? 'Vous êtes à jour. Tirez vers le bas pour actualiser.',
                      action: svc.error == null
                          ? null
                          : OutlinedButton(onPressed: svc.refresh, child: const Text('Réessayer')),
                    ),
                  ),
                ]),
              );
            }
            return RefreshIndicator(
              onRefresh: svc.refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: svc.items.length + (svc.fromCache ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  if (svc.fromCache) {
                    if (i == 0) return const OfflineBanner();
                    i -= 1;
                  }
                  final n = svc.items[i];
                  return Card(
                    color: n.lue ? null : EdColors.blue.withValues(alpha: 0.07),
                    child: ListTile(
                      leading: Icon(_icon(n.type), color: n.lue ? null : EdColors.red),
                      title: Text(n.titre,
                          style: TextStyle(
                              fontWeight: n.lue ? FontWeight.w600 : FontWeight.w800)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: 2),
                        Text(n.message),
                        const SizedBox(height: 4),
                        Text(formatDate(n.date), style: t.textTheme.bodySmall),
                      ]),
                      trailing: n.lue
                          ? null
                          : const Icon(Icons.circle, size: 10, color: EdColors.red),
                      onTap: () {
                        svc.markRead(n);
                        final link = n.lien;
                        final uri = link == null ? null : Uri.tryParse(link);
                        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
                          launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  );
                },
              ),
            );
          }),
        ),
      ]),
    );
  }
}
