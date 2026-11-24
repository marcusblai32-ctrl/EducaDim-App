import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../courses/online_pdf_screen.dart';

class DocItem {
  DocItem(this.title, this.url, this.course, this.lesson);
  final String title, url, course, lesson;
}

Future<List<DocItem>> loadDocuments(ApiClient api) async {
  try {
    final res = await api.dio.get('documents/');
    final m = res.data is Map ? res.data as Map : const {};
    return [
      for (final d in (m['documents'] as List? ?? []))
        if (d is Map && '${d['url'] ?? ''}'.isNotEmpty)
          DocItem('${d['title'] ?? ''}', '${d['url']}', '${d['course'] ?? ''}', '${d['lesson'] ?? ''}'),
    ];
  } on DioException catch (e) {
    throw mapDio(e);
  }
}

/// « Mes documents » : tous les PDF de vos cours, à lire dans l'application (jamais téléchargés).
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mes documents'))),
      body: AsyncView<List<DocItem>>(
        load: () => loadDocuments(api),
        builder: (context, docs, reload) {
          final q = _q.trim().toLowerCase();
          final shown = q.isEmpty
              ? docs
              : docs.where((d) => '${d.title} ${d.course} ${d.lesson}'.toLowerCase().contains(q)).toList();
          if (docs.isEmpty) {
            return EmptyState(
                icon: Icons.menu_book_rounded,
                title: tr('Aucun document'),
                message: tr('Les PDF de vos cours apparaîtront ici.'));
          }
          String? last;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Rechercher un document')),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 8),
              for (final d in shown) ...[
                if (d.course != last) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text(last = d.course, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(d.lesson, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => OnlinePdfScreen(d.url, title: d.title))),
                  ),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }
}
