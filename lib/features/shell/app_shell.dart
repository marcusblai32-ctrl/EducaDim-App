import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/language_button.dart';
import '../notifications/notification_service.dart';
import '../review/review_service.dart';
import '../review/review_sheet.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    ('/home', 'Accueil', Icons.home_outlined, Icons.home_rounded),
    ('/explore', 'Explorer', Icons.explore_outlined, Icons.explore_rounded),
    ('/courses', 'Mes cours', Icons.menu_book_outlined, Icons.menu_book_rounded),
    ('/profile', 'Profil', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    final idx = _tabs.indexWhere((t) => loc.startsWith(t.$1)).clamp(0, 3);
    final sync = context.watch<SyncService>();
    final unread = context.watch<NotificationService>().unread;
    final t = Theme.of(context);
    // Rappel d'avis : une fois à chaque ouverture de l'app, tant que l'utilisateur n'a pas répondu.
    final review = context.watch<ReviewService>();
    if (review.shouldPrompt) {
      review.markPrompted();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) showReviewSheet(context, reminder: true);
      });
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/logo.png', height: 30),
          const SizedBox(width: 10),
          const BrandWordmark(),
        ]),
        actions: [
          if (!sync.online || sync.pending > 0) ...[
            SyncBadge(online: sync.online, pending: sync.pending),
            const SizedBox(width: 6),
          ],
          const LanguageButton(),
          IconButton(
            tooltip: tr('Notifications'),
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: unread > 0,
              backgroundColor: EdColors.red,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: child,
      floatingActionButton: FloatingActionButton(
        tooltip: tr('Discussions'),
        onPressed: () => context.push('/chat'),
        child: const Icon(Icons.chat_bubble_rounded),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => context.go(_tabs[i].$1),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.$3),
              selectedIcon: Icon(tab.$4, color: t.colorScheme.primary),
              label: tr(tab.$2),
            ),
        ],
      ),
    );
  }
}
