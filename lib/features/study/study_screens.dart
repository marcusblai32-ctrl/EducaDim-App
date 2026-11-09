import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import 'study_service.dart';

const _dayNames = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

// ======================= Choix du rythme (premier lancement + modification) =======================

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.firstTime});
  final bool firstTime;
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late Set<int> _days;
  late TimeOfDay _time;
  late bool _ranking;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<StudyService>();
    _days = s.hasPlan ? {...s.weekdays} : {0, 2, 4};
    _time = s.hasPlan ? s.time : const TimeOfDay(hour: 18, minute: 0);
    _ranking = s.showInRanking;
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _save() async {
    if (_days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          snackBarAnimationStyle: AnimationStyle.noAnimation,
          SnackBar(content: Text('Choisissez au moins un jour.')));
      return;
    }
    setState(() => _busy = true);
    final msg = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await context.read<StudyService>().savePlan(_days, _time, _ranking);
      if (widget.firstTime) {
        router.go('/home');
      } else {
        router.pop();
      }
    } on ApiException catch (e) {
      msg.showSnackBar(
          snackBarAnimationStyle: AnimationStyle.noAnimation,
          SnackBar(content: Text(e.isOffline ? tr('Connexion requise pour enregistrer votre rythme.') : e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final presets = <String, Set<int>>{
      'Tous les jours': {0, 1, 2, 3, 4, 5, 6},
      '5 jours': {0, 1, 2, 3, 4},
      '3 jours': {0, 2, 4},
      '1 jour': {0},
    };
    return Scaffold(
      appBar: widget.firstTime ? null : AppBar(title: const Text('Mon rythme d’étude')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (widget.firstTime) ...[
            const SizedBox(height: 8),
            HeroCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFFB347), size: 40),
                const SizedBox(height: 10),
                const Text('Créez votre habitude d’étude',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                    'Choisissez les jours et l’heure où vous voulez apprendre. Nous vous rappellerons à l’heure choisie.',
                    style: TextStyle(color: Color(0xFFDDE2FF), height: 1.5)),
              ]),
            ),
            const SizedBox(height: 20),
          ],
          Text('Combien de jours par semaine ?', style: t.textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in presets.entries)
              ChoiceChip(
                label: Text(e.key),
                selected: _days.length == e.value.length && _days.containsAll(e.value),
                onSelected: (_) => setState(() => _days = {...e.value}),
              ),
          ]),
          const SizedBox(height: 18),
          Text('Quels jours ?', style: t.textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < 7; i++)
              FilterChip(
                label: Text(_dayNames[i]),
                selected: _days.contains(i),
                showCheckmark: false,
                selectedColor: t.colorScheme.primary,
                labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _days.contains(i) ? t.colorScheme.onPrimary : null),
                onSelected: (v) => setState(() => v ? _days.add(i) : _days.remove(i)),
              ),
          ]),
          const SizedBox(height: 6),
          Text(tr('{n} jour(s) par semaine', {'n': _days.length}),
              style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          Text('À quelle heure ?', style: t.textTheme.titleMedium),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.alarm_rounded),
              title: Text(_time.format(context), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              subtitle: const Text('Heure du rappel'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickTime,
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: SwitchListTile(
              title: const Text('Apparaître dans le classement des séries', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Les autres voient votre prénom, votre série et un point vert quand vous êtes en ligne.'),
              value: _ranking,
              onChanged: (v) => setState(() => _ranking = v),
            ),
          ),
          const SizedBox(height: 14),
          Text(
              'Une série compte vos jours d’affilée. Si vous manquez un jour prévu, elle repart de zéro.',
              style: t.textTheme.bodySmall?.copyWith(height: 1.5)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(widget.firstTime ? 'Commencer' : 'Enregistrer'),
          ),
        ]),
      ),
    );
  }
}

// ======================= Classement des séries =======================

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final study = context.read<StudyService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Classement des séries')),
      body: AsyncView<LeaderData>(
        load: study.leaderboard,
        builder: (context, d, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            HeroCard(
              child: Row(children: [
                const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFFB347), size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('{n} jours d’affilée', {'n': d.myStreak}),
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(d.myRank == null ? tr('Connectez-vous chaque jour prévu pour entrer au classement.')
                        : tr('Vous êtes n° {r}', {'r': d.myRank}),
                        style: const TextStyle(color: Color(0xFFDDE2FF))),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            if (d.rows.isEmpty)
              const SizedBox(
                  height: 260,
                  child: EmptyState(
                      icon: Icons.local_fire_department_outlined,
                      title: 'Aucune série en cours',
                      message: 'Soyez le premier : connectez-vous chaque jour prévu !'))
            else
              for (final r in d.rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    color: r.me ? EdColors.blue.withValues(alpha: 0.08) : null,
                    child: ListTile(
                      leading: Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(
                            width: 26,
                            child: Text('${r.rank}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w900))),
                        const SizedBox(width: 8),
                        InitialsAvatar(r.name, size: 42, online: r.online),
                      ]),
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF8A00), size: 20),
                        const SizedBox(width: 4),
                        Text('${r.streak}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ]),
                    ),
                  ),
                ),
          ]),
        ),
      ),
    );
  }
}

// ======================= Carte « série » de l'accueil =======================

class StreakCard extends StatelessWidget {
  const StreakCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<StudyService>();
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/leaderboard'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: const Color(0xFFFF8A00).withValues(alpha: 0.14), shape: BoxShape.circle),
                child: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF8A00), size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('{n} jours d’affilée', {'n': s.streak}), style: t.textTheme.titleLarge),
                  Text(tr('Meilleure série : {n} · Prochain palier : {m} jours', {
                    'n': s.best,
                    'm': (s.streak ~/ 7 + 1) * 7,
                  }), style: TextStyle(fontSize: 12, color: muted)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: muted),
            ]),
            if (s.week.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (var i = 0; i < s.week.length; i++) _Dot(s.week[i], tr(_dayNames[i])[0]),
              ]),
            ],
            if (s.streakLost) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: EdColors.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.refresh_rounded, size: 18, color: EdColors.warn),
                  const SizedBox(width: 8),
                  const Expanded(
                      child: Text('Votre série a été remise à zéro. On recommence aujourd’hui !',
                          style: TextStyle(fontSize: 12.5))),
                  InkWell(onTap: s.dismissLost, child: const Icon(Icons.close_rounded, size: 18)),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.d, this.letter);
  final StudyDay d;
  final String letter;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final missed = d.planned && !d.done && !d.today && d.date.isBefore(DateTime.now());
    Color bg = Colors.transparent;
    Color border = t.dividerColor;
    Widget child = Text(letter, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: d.planned ? null : t.dividerColor));
    if (d.done) {
      bg = EdColors.good;
      border = EdColors.good;
      child = const Icon(Icons.check_rounded, size: 18, color: Colors.white);
    } else if (missed) {
      border = EdColors.red;
    } else if (d.today) {
      border = t.colorScheme.primary;
    }
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: d.today ? 2.2 : 1.4),
      ),
      child: child,
    );
  }
}
