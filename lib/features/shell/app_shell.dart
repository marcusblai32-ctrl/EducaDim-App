import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/common.dart';
import '../notifications/notification_service.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    ('/home', 'Accueil', Icons.home_outlined, Icons.home),
    ('/explore', 'Explorer', Icons.search, Icons.search),
    ('/courses', 'Mes cours', Icons.menu_book_outlined, Icons.menu_book),
    ('/profile', 'Profil', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    final idx = _tabs.indexWhere((t) => loc.startsWith(t.$1)).clamp(0, 3);
    final sync = context.watch<SyncService>();
    final unread = context.watch<NotificationService>().unread;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/logo.png', height: 32),
          const SizedBox(width: 8),
          Text.rich(TextSpan(
            text: 'Educa',
            style: t.textTheme.titleLarge,
            children: const [TextSpan(text: 'Dim', style: TextStyle(color: EdColors.red))],
          )),
        ]),
        actions: [
          SyncBadge(online: sync.online, pending: sync.pending),
          IconButton(
            tooltip: unread > 0 ? 'Notifications ($unread non lues)' : 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: child,
      floatingActionButton: FloatingActionButton(
        backgroundColor: EdColors.red,
        foregroundColor: Colors.white,
        tooltip: 'Ouvrir le chat',
        onPressed: () => context.push('/chat'),
        child: const Icon(Icons.chat_bubble_rounded),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => context.go(_tabs[i].$1),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.$3),
              selectedIcon: Icon(tab.$4, color: EdColors.red),
              label: tab.$2,
            ),
        ],
      ),
    );
  }
}
