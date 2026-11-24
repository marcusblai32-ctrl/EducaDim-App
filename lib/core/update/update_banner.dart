import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import '../i18n/text.dart';

/// Version de CETTE application. À AUGMENTER à chaque nouvelle APK publiée (ex. 1.1.0 → 1.2.0).
/// Le site (admin > Versions téléchargeables > Application « EducaDim », Plateforme « Android ») doit avoir une
/// version PLUS GRANDE pour que l'application propose la mise à jour.
const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.1.0');

int _cmp(String a, String b) {
  List<int> p(String v) =>
      v.split('+').first.split('.').map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
  final x = p(a), y = p(b);
  final n = x.length > y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final u = i < x.length ? x[i] : 0, v = i < y.length ? y[i] : 0;
    if (u != v) return u.compareTo(v);
  }
  return 0;
}

class _Upd {
  _Upd(this.version, this.url, this.notes, this.critical);
  final String version, url;
  final List<String> notes;
  final bool critical;
}

Future<_Upd?> _check() async {
  try {
    final res = await Dio().get<dynamic>(
      '${ApiConfig.siteUrl}/api/v1/releases/',
      queryParameters: {'app': 'educadim', 'platform': 'android'},
      options: Options(receiveTimeout: const Duration(seconds: 12), sendTimeout: const Duration(seconds: 12)),
    );
    final data = res.data;
    final rows = data is Map ? data['results'] : null;
    if (rows is! List) return null;
    Map? best;
    var critical = false;
    for (final r in rows.whereType<Map>()) {
      if (r['prerelease'] == true || r['download'] == null) continue;
      final v = '${r['version']}';
      if (_cmp(v, kAppVersion) <= 0) continue;
      if (r['critical'] == true) critical = true;
      if (best == null || _cmp(v, '${best['version']}') > 0) best = r;
    }
    if (best == null) return null;
    return _Upd('${best['version']}', '${best['download']}',
        [for (final n in (best['notes'] as List? ?? [])) '$n'], critical);
  } catch (_) {
    return null; // jamais d'erreur visible : pas de réseau = pas de mise à jour proposée
  }
}

/// Bandeau « Nouvelle version disponible » au-dessus de l'application (toucher = ouvre le téléchargement).
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});
  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  _Upd? _u;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _check().then((u) {
      if (mounted && u != null) setState(() => _u = u);
    });
  }

  void _open(_Upd u) {
    showDialog<void>(
      context: context,
      barrierDismissible: !u.critical,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Version {v} disponible', {'v': u.version})),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Vous avez la version {v}.', {'v': kAppVersion})),
            if (u.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(tr('Nouveautés'), style: const TextStyle(fontWeight: FontWeight.w700)),
              for (final n in u.notes) Text('• $n'),
            ],
          ]),
        ),
        actions: [
          if (!u.critical) TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Plus tard'))),
          FilledButton(
            onPressed: () => launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication),
            child: Text(tr('Télécharger')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    if (u == null || (_hidden && !u.critical)) return const SizedBox.shrink();
    final s = Theme.of(context).colorScheme;
    return Material(
      color: u.critical ? s.errorContainer : s.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Icon(Icons.system_update_rounded, size: 20, color: s.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _open(u),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr('Nouvelle version {v} disponible — toucher pour mettre à jour', {'v': u.version}),
                    style: TextStyle(fontWeight: FontWeight.w700, color: s.onPrimaryContainer)),
              ),
            ),
          ),
          if (!u.critical)
            IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _hidden = true)),
        ]),
      ),
    );
  }
}
