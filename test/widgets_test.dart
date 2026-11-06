import 'package:educadim/core/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EmptyState affiche titre, message et action', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmptyState(
          icon: Icons.school_outlined,
          title: 'Aucune formation',
          message: 'Rien à afficher.',
          action: TextButton(onPressed: () {}, child: const Text('Réessayer')),
        ),
      ),
    ));
    expect(find.text('Aucune formation'), findsOneWidget);
    expect(find.text('Rien à afficher.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('SyncBadge : hors ligne / en attente / à jour', (tester) async {
    Future<void> show(bool online, int pending) => tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SyncBadge(online: online, pending: pending))));
    await show(false, 0);
    expect(find.text('Hors ligne'), findsOneWidget);
    await show(true, 3);
    expect(find.text('3 en attente'), findsOneWidget);
    await show(true, 0);
    expect(find.text('À jour'), findsOneWidget);
  });
}
