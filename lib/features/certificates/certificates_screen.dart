import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/db/cache_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../courses/course_widgets.dart';
import '../courses/models.dart' show Loaded, formatDate;

class CertificateItem {
  CertificateItem(this.publicId, this.number, this.courseTitle, this.studentName, this.status,
      this.statusLabel, this.editable, this.reviewNote, this.issuedAt, this.verifyUrl,
      this.downloadPageUrl);
  final String publicId, number, courseTitle, studentName, status, statusLabel, verifyUrl,
      downloadPageUrl;
  final bool editable;
  final String? reviewNote;
  final DateTime? issuedAt;

  static List<CertificateItem> listFromJson(dynamic j) {
    final raw = j is Map && j['certificates'] is List ? j['certificates'] as List : const [];
    String s(Map m, String k) => m[k] is String ? m[k] as String : '';
    return raw.whereType<Map>().map((m) {
      return CertificateItem(
        s(m, 'public_id'),
        s(m, 'number'),
        s(m, 'course_title'),
        s(m, 'student_name'),
        s(m, 'status'),
        s(m, 'status_label'),
        m['editable'] == true,
        m['review_note'] is String ? m['review_note'] as String : null,
        DateTime.tryParse(s(m, 'issued_at'))?.toLocal(),
        s(m, 'verify_url'),
        s(m, 'download_page_url'),
      );
    }).toList();
  }
}

class CertificateRepository {
  CertificateRepository(this._api, this._cache);
  final ApiClient _api;
  final CacheStore _cache;

  Future<Loaded<List<CertificateItem>>> list() async {
    try {
      final res = await _api.dio.get('certificates/');
      await _cache.put('certificates', res.data);
      return Loaded(CertificateItem.listFromJson(res.data));
    } on DioException catch (e) {
      final ex = mapDio(e);
      if (ex.isOffline) {
        final c = await _cache.get('certificates');
        if (c != null) return Loaded(CertificateItem.listFromJson(c), fromCache: true);
      }
      throw ex;
    }
  }
}

class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key});
  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  @override
  Widget build(BuildContext context) {
    final repo = context.read<CertificateRepository>();
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes certificats')),
      body: AsyncView<Loaded<List<CertificateItem>>>(
        load: () async {
          try {
            return await repo.list();
          } on ApiException catch (e) {
            if (e.statusCode == 404) {
              throw ApiException('Les certificats ne sont pas encore disponibles sur le serveur '
                  '(mise à jour du backend nécessaire).');
            }
            rethrow;
          }
        },
        builder: (context, r, reload) {
          if (r.value.isEmpty) {
            return const EmptyState(
                icon: Icons.workspace_premium_outlined,
                title: 'Aucun certificat',
                message: 'Terminez un cours à 100 % pour obtenir votre certificat.');
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (r.fromCache) const OfflineBanner(),
              for (final c in r.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.workspace_premium_outlined,
                              color: c.status == 'issued' ? EdColors.good : EdColors.blue),
                          const SizedBox(width: 10),
                          Expanded(child: Text(c.courseTitle, style: t.textTheme.titleMedium)),
                        ]),
                        const SizedBox(height: 6),
                        Text('${c.statusLabel} · N° ${c.number}',
                            style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.65))),
                        const SizedBox(height: 4),
                        Text('Nom : ${c.studentName}'),
                        if (c.issuedAt != null) Text('Délivré le ${formatDate(c.issuedAt)}'),
                        if ((c.reviewNote ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Note de l’équipe : ${c.reviewNote}',
                              style: const TextStyle(fontStyle: FontStyle.italic)),
                        ],
                        const SizedBox(height: 12),
                        if (c.status == 'issued')
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Télécharger sur le site'),
                              onPressed: () => launchUrl(Uri.parse(c.downloadPageUrl),
                                  mode: LaunchMode.externalApplication),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                              icon: const Icon(Icons.verified_outlined),
                              label: const Text('Vérification en ligne'),
                              onPressed: () => launchUrl(Uri.parse(c.verifyUrl),
                                  mode: LaunchMode.externalApplication),
                            ),
                          ])
                        else
                          Text(
                              c.editable
                                  ? 'Complétez ou vérifiez le nom à imprimer sur le site EducaDim '
                                      '(rubrique Certificats) pour lancer la vérification.'
                                  : 'Votre certificat est en cours de traitement par l’équipe.',
                              style: t.textTheme.bodySmall?.copyWith(height: 1.5)),
                      ]),
                    ),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
