import 'package:flutter/material.dart';
import '../../core/widgets/common.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) => const SafeArea(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: PageHeader('Centre de notifications', 'Vos actualités'),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'Aucune notification',
              message:
                  'L’API mobile n’expose pas encore d’endpoint de notifications ni '
                  'de notifications push (voir docs/API_CONTRACT.md).',
            ),
          ),
        ]),
      );
}
