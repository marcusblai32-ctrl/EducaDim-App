import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import '../i18n/text.dart';

/// Version installée de l'application.
/// À CHANGER à chaque nouvelle version publiée (même numéro que dans « Versions téléchargeables » du site).
/// On peut aussi la fixer à la compilation : --dart-define=APP_VERSION=1.2.0
const String kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

class AppUpdateInfo {
  AppUpdateInfo({required this.version, required this.title, required this.notes, required this.download, required this.critical});
  final String version;
  final String title;
  final List<String> notes;
  final String download;
  final bool critical;
}

class AppUpdateChecker {
  static String? get _platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    return null;
  }

  /// true si [a] est plus récente que [b] (comparaison 1.10.0 > 1.9.2).
  static bool isNewer(String a, String b) {
    List<int> parse(String v) =>
        RegExp(r'\d+').allMatches(v.split('+').first).map((m) => int.parse(m.group(0)!)).toList();
    final x = parse(a), y = parse(b);
    for (var i = 0; i < 4; i++) {
      final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
      if (p != q) return p > q;
    }
    return false;
  }

  /// Interroge le site (page « Téléchargements ») ; renvoie la mise à jour disponible ou null.
  static Future<AppUpdateInfo?> check() async {
    final platform = _platform;
    if (platform == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse('${ApiConfig.siteUrl}/api/v1/releases/?app=educadim&platform=$platform');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final results = (data['results'] as List? ?? const []).cast<Map<String, dynamic>>();
      // Résultats triés du plus récent au plus ancien : on prend la plus récente version stable.
      for (final r in results) {
        if (r['prerelease'] == true) continue;
        final v = (r['version'] ?? '').toString();
        final dl = (r['download'] ?? '').toString();
        if (v.isEmpty || dl.isEmpty) continue;
        if (!isNewer(v, kAppVersion)) return null;
        return AppUpdateInfo(
          version: v,
          title: (r['title'] ?? '').toString(),
          notes: ((r['notes'] as List?) ?? const []).map((e) => e.toString()).toList(),
          download: dl,
          critical: r['critical'] == true,
        );
      }
      return null;
    } catch (_) {
      return null; // pas d'internet ou site indisponible : on ne dérange pas l'utilisateur
    } finally {
      client.close(force: true);
    }
  }
}

/// Enveloppe l'écran principal : à l'ouverture, si une version plus récente est publiée,
/// affiche une fenêtre « Mise à jour disponible » avec le bouton « Mettre à jour ».
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;
  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  static bool _checkedThisSession = false;

  @override
  void initState() {
    super.initState();
    if (_checkedThisSession) return;
    _checkedThisSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final info = await AppUpdateChecker.check();
    if (info == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'update_snooze_${info.version}';
    final last = prefs.getInt(key) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Mise à jour normale : un rappel par jour au maximum. Mise à jour importante : à chaque ouverture.
    if (!info.critical && now - last < const Duration(hours: 24).inMilliseconds) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !info.critical,
      builder: (ctx) => PopScope(
        canPop: !info.critical,
        child: AlertDialog(
          icon: const Icon(Icons.system_update_rounded, size: 32),
          title: Text(info.critical ? 'Mise à jour importante' : 'Mise à jour disponible'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Version ${info.version}', style: const TextStyle(fontWeight: FontWeight.w800)),
              if (info.title.isNotEmpty) Text(info.title),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final n in info.notes.take(8)) Text('• $n'),
              ],
            ]),
          ),
          actions: [
            if (!info.critical)
              TextButton(
                onPressed: () {
                  prefs.setInt(key, now);
                  Navigator.of(ctx).pop();
                },
                child: Text('Plus tard'),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: Text('Mettre à jour'),
              onPressed: () => launchUrl(Uri.parse(info.download), mode: LaunchMode.externalApplication),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
