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
                  'Le backend ne fournit pas encore de flux de notifications ni de '
                  'notifications push confirmés. L’écran est prêt à les afficher '
                  '(lu/non lu) dès que le contrat sera défini '
                  '(docs/API_CONTRACT.md).',
            ),
          ),
        ]),
      );
}
