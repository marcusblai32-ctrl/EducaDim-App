import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';

/// Classement par points (leçons, quiz, cours terminés, présences) et badges.
/// Données : GET ranking/?period=… et GET badges/ (voir mobile_api/ranking_views.py).

class PointsRow {
  PointsRow(this.rank, this.name, this.points, this.me);
  final int rank;
  final String name;
  final int points;
  final bool me;
}

class PointsBoard {
  PointsBoard(this.rows, this.myRank, this.myPoints, this.total, this.level, this.nextLevel,
      this.nextLevelPoints);
  final List<PointsRow> rows;
  final int? myRank;
  final int myPoints, total;
  final String? level, nextLevel;
  final int? nextLevelPoints;
}

class BadgeItem {
  BadgeItem(this.name, this.description, this.image, this.earned, this.holders);
  final String name, description, image;
  final bool earned;
  final int holders;
}

class RankingRepository {
  RankingRepository(this._api);
  final ApiClient _api;

  Future<PointsBoard> board(String period) async {
    try {
      final res = await _api.dio.get('ranking/', queryParameters: {'period': period});
      final m = res.data is Map ? res.data as Map : const {};
      final rows = <PointsRow>[
        for (final r in (m['leaders'] as List? ?? []))
          if (r is Map)
            PointsRow(r['rank'] as int? ?? 0, '${r['name'] ?? ''}', r['points'] as int? ?? 0,
                r['me'] == true),
      ];
      final me = m['me'] is Map ? m['me'] as Map : const {};
      return PointsBoard(rows, me['rank'] as int?, me['points'] as int? ?? 0,
          me['total'] as int? ?? 0, me['level'] as String?, me['next_level'] as String?,
          me['next_level_points'] as int?);
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  Future<List<BadgeItem>> badges() async {
    try {
      final res = await _api.dio.get('badges/');
      final m = res.data is Map ? res.data as Map : const {};
      return [
        for (final b in (m['badges'] as List? ?? []))
          if (b is Map)
            BadgeItem('${b['name'] ?? ''}', '${b['description'] ?? ''}', '${b['image'] ?? ''}',
                b['earned'] == true, b['holders'] as int? ?? 0),
      ];
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }
}

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});
  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  String _period = 'total';

  @override
  Widget build(BuildContext context) {
    final repo = RankingRepository(context.read<ApiClient>());
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.65);
    return Scaffold(
      appBar: AppBar(title: const Text('Classement')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'total', label: Text('Général')),
                ButtonSegment(value: 'semaine', label: Text('Semaine')),
                ButtonSegment(value: 'mois', label: Text('Mois')),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
          ),
        ),
        Expanded(
          child: AsyncView<PointsBoard>(
            key: ValueKey(_period),
            load: () => repo.board(_period),
            builder: (context, b, reload) {
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.emoji_events_rounded, color: EdColors.warn),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                                b.myRank == null
                                    ? tr('Pas encore classé')
                                    : tr('Vous êtes {r}e', {'r': b.myRank}),
                                style: t.textTheme.titleMedium),
                          ),
                          Text(tr('{p} pts', {'p': b.myPoints}),
                              style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        ]),
                        if (b.level != null) ...[
                          const SizedBox(height: 8),
                          Text(tr('Niveau : {n}', {'n': b.level}), style: TextStyle(color: muted)),
                        ],
                        if (b.nextLevel != null && b.nextLevelPoints != null) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: 8,
                              value: (b.total / b.nextLevelPoints!).clamp(0.0, 1.0).toDouble(),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                              tr('Prochain niveau : {n} ({p} pts)',
                                  {'n': b.nextLevel, 'p': b.nextLevelPoints}),
                              style: t.textTheme.bodySmall?.copyWith(color: muted)),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (b.rows.isEmpty)
                    const EmptyState(
                        icon: Icons.leaderboard_rounded,
                        title: 'Aucun point pour le moment',
                        message:
                            'Terminez une leçon, réussissez un quiz ou venez en cours pour gagner des points.')
                  else
                    for (final r in b.rows)
                      Card(
                        color: r.me ? EdColors.blue.withValues(alpha: 0.08) : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: r.rank <= 3
                                ? EdColors.warn.withValues(alpha: 0.2)
                                : t.colorScheme.surfaceContainerHighest,
                            child: Text('${r.rank}',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text(tr('{p} pts', {'p': r.points}),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class BadgesScreen extends StatelessWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = RankingRepository(context.read<ApiClient>());
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes badges')),
      body: AsyncView<List<BadgeItem>>(
        load: repo.badges,
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return const EmptyState(
                icon: Icons.military_tech_outlined,
                title: 'Aucun badge',
                message: 'Les badges apparaîtront ici dès que l’équipe en aura créé.');
          }
          final earned = items.where((b) => b.earned).length;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(tr('{a} badge(s) obtenu(s) sur {b}', {'a': earned, 'b': items.length}),
                  style: t.textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final b in items)
                Card(
                  child: Opacity(
                    opacity: b.earned ? 1 : 0.55,
                    child: ListTile(
                      leading: b.image.isEmpty
                          ? Icon(b.earned ? Icons.military_tech_rounded : Icons.lock_outline_rounded,
                              size: 36, color: b.earned ? EdColors.warn : null)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(b.image,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.military_tech_rounded)),
                            ),
                      title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(b.description.isEmpty
                          ? (b.earned ? tr('Obtenu') : tr('À débloquer'))
                          : b.description),
                      trailing: b.earned
                          ? const Icon(Icons.check_circle_rounded, color: EdColors.good)
                          : null,
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
