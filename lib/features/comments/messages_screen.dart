import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/i18n/text.dart';
import '../../core/widgets/common.dart';
import 'comments_service.dart';

String _fmt(DateTime d) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
}

Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Messages du professeur : lecture seule, par cours. `courseId` = un seul cours (depuis la page du cours).
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, this.courseId});
  final int? courseId;
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<CommentsService>().maybeFetch());
  }

  Future<void> _refresh(CommentsService s) async {
    if (!s.canRefreshManually) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Déjà à jour. Réessayez plus tard.'))));
      return;
    }
    await s.fetch();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<CommentsService>();
    final list = widget.courseId == null ? s.courses : s.courses.where((c) => c.courseId == widget.courseId).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Messages du professeur'))),
      body: RefreshIndicator(
        onRefresh: () => _refresh(s),
        child: list.isEmpty
            ? ListView(children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.mark_email_unread_outlined,
                  title: tr('Aucun message pour le moment'),
                  message: tr('Les messages de vos professeurs apparaîtront ici. Ils se mettent à jour une fois par jour, dès que vous êtes connecté.'),
                ),
              ])
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [for (final c in list) _CourseCard(c)],
              ),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard(this.c);
  final CourseMessages c;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text('${c.headcount} ${tr('étudiants inscrits')}', style: Theme.of(context).textTheme.bodySmall),
          if (c.groupUrl.isNotEmpty || c.teacherUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (c.groupUrl.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _open(c.groupUrl),
                  icon: const Icon(Icons.groups_rounded),
                  label: Text(tr('Groupe WhatsApp du cours')),
                ),
              if (c.teacherUrl.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _open(c.teacherUrl),
                  icon: const Icon(Icons.chat_rounded),
                  label: Text(tr('Écrire au professeur')),
                ),
            ]),
          ],
          const Divider(height: 24),
          if (c.comments.isEmpty)
            Text(tr('Aucun message pour le moment'), style: Theme.of(context).textTheme.bodySmall)
          else
            for (final m in c.comments)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${m.createdAt == null ? '' : _fmt(m.createdAt!)}${m.personal ? ' · ${tr('Message personnel')}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(m.text),
                ]),
              ),
        ]),
      ),
    );
  }
}
