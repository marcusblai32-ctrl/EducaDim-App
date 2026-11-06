import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import 'course_repository.dart';
import 'course_widgets.dart';
import 'models.dart';
import 'progress_service.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _prix; // null | gratuit | payant

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _query = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CourseRepository>();
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const PageHeader('Catalogue', 'Trouvez votre prochaine formation'),
            TextField(
              controller: _ctrl,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher un cours ou un sujet…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final f in const [(null, 'Tout'), ('gratuit', 'Gratuit'), ('payant', 'Payant')])
                ChoiceChip(
                  label: Text(f.$2),
                  selected: _prix == f.$1,
                  onSelected: (_) => setState(() => _prix = f.$1),
                ),
            ]),
          ]),
        ),
        Expanded(
          child: AsyncView<Loaded<CoursePage>>(
            key: ValueKey('$_query|$_prix'),
            load: () => repo.catalog(search: _query, prix: _prix),
            builder: (context, r, reload) {
              final courses = r.value.results;
              final progress = context.watch<ProgressService>();
              if (courses.isEmpty) {
                return const EmptyState(
                    icon: Icons.search_off,
                    title: 'Aucune formation',
                    message: 'Aucun cours ne correspond à votre recherche.');
              }
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: courses.length + (r.fromCache ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (_, i) {
                    if (r.fromCache) {
                      if (i == 0) return const OfflineBanner();
                      i -= 1;
                    }
                    return CourseCard(courses[i],
                        doneLessons: progress.doneInCourse(courses[i].id));
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
