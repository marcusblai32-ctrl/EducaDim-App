import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/common.dart';
import 'course_repository.dart';

class _CourseListScreen extends StatelessWidget {
  const _CourseListScreen(this.kicker, this.title, this.load);
  final String kicker;
  final String title;
  final Future<List<Map<String, dynamic>>> Function(CourseRepository) load;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CourseRepository>();
    return SafeArea(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: load(repo),
        builder: (context, snap) {
          Widget body;
          if (snap.connectionState != ConnectionState.done) {
            body = const Center(child: CircularProgressIndicator());
          } else if (snap.error is ContractMissing) {
            final e = snap.error as ContractMissing;
            body = EmptyState(
              icon: Icons.link_off_rounded,
              title: 'Connexion au serveur à finaliser',
              message: '${e.needs}. Cet écran affichera les données réelles '
                  'dès que le contrat API sera confirmé '
                  '(docs/API_CONTRACT.md). Aucune donnée fictive n’est affichée.',
            );
          } else if (snap.hasError) {
            body = EmptyState(
                icon: Icons.error_outline,
                title: 'Chargement impossible',
                message: ApiException.from(snap.error!).message);
          } else {
            body = const EmptyState(
                icon: Icons.school_outlined,
                title: 'Aucun cours',
                message: 'Rien à afficher pour le moment.');
          }
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: PageHeader(kicker, title),
            ),
            Expanded(child: body),
          ]);
        },
      ),
    );
  }
}

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      _CourseListScreen('Catalogue', 'Trouvez votre prochaine formation', (r) => r.catalog());
}

class MyCoursesScreen extends StatelessWidget {
  const MyCoursesScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      _CourseListScreen('Votre apprentissage', 'Mes formations', (r) => r.myEnrollments());
}
