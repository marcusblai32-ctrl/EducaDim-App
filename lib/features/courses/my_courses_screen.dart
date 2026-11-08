import 'package:flutter/material.dart' hide Text;
import '../../core/i18n/text.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import 'course_repository.dart';
import 'course_widgets.dart';
import 'models.dart';
import 'progress_service.dart';

class MyCoursesScreen extends StatelessWidget {
  const MyCoursesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<CourseRepository>();
    final progress = context.watch<ProgressService>();
    return SafeArea(
      child: AsyncView<Loaded<List<Course>>>(
        load: repo.myCourses,
        builder: (context, r, reload) {
          final courses = r.value;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
              const PageHeader('Votre apprentissage', 'Mes formations',
                  subtitle: 'Cours gratuits, inscriptions actives et abonnements.'),
              if (r.fromCache) const OfflineBanner(),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('Mes téléchargements'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/downloads'),
                ),
              ),
              const SizedBox(height: 14),
              if (courses.isEmpty)
                const SizedBox(
                  height: 280,
                  child: EmptyState(
                      icon: Icons.school_outlined,
                      title: 'Aucune formation',
                      message:
                          'Vous n’avez accès à aucun cours pour le moment. Explorez le catalogue.'),
                )
              else
                for (final c in courses) ...[
                  CourseCard(c, doneLessons: progress.doneInCourse(c.id)),
                  const SizedBox(height: 14),
                ],
            ]),
          );
        },
      ),
    );
  }
}
