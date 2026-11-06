import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/api_config.dart';
import '../../core/db/outbox_repository.dart';
import '../../core/network/api_exception.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import 'course_repository.dart';
import 'course_widgets.dart';
import 'models.dart';

// ======================= Liste des quiz d'un cours =======================

class QuizListScreen extends StatelessWidget {
  const QuizListScreen(this.courseId, {super.key});
  final int courseId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CourseRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      body: AsyncView<Loaded<List<QuizSummary>>>(
        load: () async {
          try {
            return await repo.quizzes(courseId);
          } on ApiException catch (e) {
            if (e.statusCode == 404) {
              throw ApiException('Les quiz ne sont pas encore disponibles sur le serveur '
                  '(mise à jour du backend nécessaire).');
            }
            rethrow;
          }
        },
        builder: (context, r, reload) {
          final list = r.value;
          if (list.isEmpty) {
            return const EmptyState(
                icon: Icons.quiz_outlined,
                title: 'Aucun quiz',
                message: 'Ce cours n’a pas encore de quiz publié.');
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (r.fromCache) const OfflineBanner(),
              for (final q in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: Icon(q.passed ? Icons.check_circle : Icons.quiz_outlined,
                          color: q.passed ? EdColors.good : EdColors.blue),
                      title: Text(q.titre),
                      subtitle: Text(
                        q.compatible
                            ? '${q.questions} question(s) · ${q.duree} min · réussite ${q.passPct} %'
                                '${q.bestScore != null ? ' · meilleur : ${q.bestScore!.toStringAsFixed(0)} %' : ''}'
                            : 'Contient des questions audio/vidéo/fichier : à passer sur le site.',
                      ),
                      trailing: q.compatible
                          ? const Icon(Icons.chevron_right)
                          : const Icon(Icons.open_in_new),
                      onTap: () => q.compatible
                          ? context.push('/quiz/${q.id}')
                          : launchUrl(Uri.parse(ApiConfig.siteUrl),
                              mode: LaunchMode.externalApplication),
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

// ======================= Introduction =======================

class QuizIntroScreen extends StatefulWidget {
  const QuizIntroScreen(this.quizId, {super.key});
  final int quizId;
  @override
  State<QuizIntroScreen> createState() => _QuizIntroScreenState();
}

class _QuizIntroScreenState extends State<QuizIntroScreen> {
  bool _starting = false;

  Future<void> _start(QuizDetail quiz) async {
    setState(() => _starting = true);
    final msg = ScaffoldMessenger.of(context);
    try {
      final attempt = await context.read<CourseRepository>().startQuiz(quiz.id);
      if (mounted) context.pushReplacement('/quiz/${quiz.id}/take', extra: QuizRun(quiz, attempt));
    } on ApiException catch (e) {
      msg.showSnackBar(SnackBar(
          content: Text(e.isOffline
              ? 'Connexion requise pour démarrer le quiz (une seule fois). Réessayez en ligne.'
              : e.message)));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CourseRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      body: AsyncView<Loaded<QuizDetail>>(
        load: () => repo.quiz(widget.quizId),
        builder: (context, r, _) {
          final q = r.value;
          final t = Theme.of(context);
          return ListView(padding: const EdgeInsets.all(16), children: [
            HeroCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Eyebrow('Évaluation', color: Color(0xFF83DCE5)),
                const SizedBox(height: 8),
                Text(q.titre,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('${q.questions.length} question(s) · ${q.duree} min · réussite à ${q.passPct} %',
                    style: const TextStyle(color: Color(0xFFD3E2E9))),
              ]),
            ),
            if (q.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(q.description, style: t.textTheme.bodyMedium?.copyWith(height: 1.5)),
            ],
            const SizedBox(height: 12),
            const Text(
                'Le chronomètre démarre dès que vous commencez. Vous pouvez terminer le quiz '
                'hors ligne : vos réponses seront envoyées automatiquement au retour de la connexion.',
                style: TextStyle(height: 1.5)),
            const SizedBox(height: 18),
            if (!q.compatible)
              const Text('Ce quiz contient des questions non prises en charge sur mobile.',
                  style: TextStyle(color: EdColors.red, fontWeight: FontWeight.w700))
            else
              FilledButton(
                onPressed: _starting ? null : () => _start(q),
                child: _starting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Commencer le quiz'),
              ),
          ]);
        },
      ),
    );
  }
}

// ======================= Passage du quiz =======================

class _Ans {
  final Set<int> ids = {};
  String text = '';
  bool get answered => ids.isNotEmpty || text.trim().isNotEmpty;
}

class QuizTakeScreen extends StatefulWidget {
  const QuizTakeScreen(this.run, {super.key});
  final QuizRun run;
  @override
  State<QuizTakeScreen> createState() => _QuizTakeScreenState();
}

class _QuizTakeScreenState extends State<QuizTakeScreen> {
  late final List<QuizQuestion> _qs =
      widget.run.quiz.questions.where((q) => q.supported).toList();
  final Map<int, _Ans> _ans = {};
  int _i = 0;
  bool _busy = false;
  Timer? _timer;
  Duration _left = Duration.zero;
  bool _hadTime = false;
  final _textCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final exp = widget.run.attempt.expiresAt;
    if (exp != null) {
      _left = exp.difference(DateTime.now());
      if (_left.isNegative) _left = Duration.zero;
      _hadTime = _left > Duration.zero;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _left <= Duration.zero) return;
      setState(() => _left -= const Duration(seconds: 1));
      // Auto-envoi seulement si le temps s'écoule pendant la séance.
      if (_left <= Duration.zero && _hadTime && !_busy) _submit(auto: true);
    });
    _syncText();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _textCtrl.dispose();
    super.dispose();
  }

  _Ans _a(QuizQuestion q) => _ans.putIfAbsent(q.id, _Ans.new);

  void _syncText() => _textCtrl.text = _qs.isEmpty ? '' : _a(_qs[_i]).text;

  void _go(int to) {
    setState(() => _i = to);
    _syncText();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(100).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _confirmAndSubmit() async {
    final missing = _qs.where((q) => !_a(q).answered).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Terminer le quiz ?'),
        content: Text(missing == 0
            ? 'Vos réponses vont être envoyées.'
            : '$missing question(s) sans réponse. Terminer quand même ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Continuer')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Terminer')),
        ],
      ),
    );
    if (ok == true) _submit();
  }

  Future<void> _submit({bool auto = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    _timer?.cancel();
    final answers = [
      for (final q in _qs)
        {
          'question_id': q.id,
          'reponse_ids': _a(q).ids.toList(),
          'texte': _a(q).text,
        }
    ];
    final repo = context.read<CourseRepository>();
    final outbox = context.read<OutboxRepository>();
    final sync = context.read<SyncService>();
    final msg = ScaffoldMessenger.of(context);
    final attemptId = widget.run.attempt.attemptId;
    try {
      await repo.submitQuiz(attemptId, answers);
    } on ApiException catch (e) {
      final retryable = e.isOffline || (e.statusCode ?? 0) >= 500;
      if (retryable) {
        // Hors ligne : réponses conservées dans la file, envoyées au retour du réseau.
        await outbox.enqueue(
          'quiz_submit',
          {'attempt_id': attemptId, 'quiz_id': widget.run.quiz.id, 'answers': answers},
          id: 'quiz-submit-$attemptId',
        );
        await sync.refreshCount();
      } else {
        msg.showSnackBar(SnackBar(content: Text(e.message)));
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    if (mounted) context.pushReplacement('/quiz-result/$attemptId');
  }

  @override
  Widget build(BuildContext context) {
    if (_qs.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: const Text('Quiz')),
          body: const EmptyState(
              icon: Icons.quiz_outlined,
              title: 'Aucune question',
              message: 'Ce quiz ne contient aucune question compatible.'));
    }
    final q = _qs[_i];
    final a = _a(q);
    final t = Theme.of(context);
    final urgent = _left.inSeconds <= 60 && _left > Duration.zero;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Quitter le quiz ?'),
            content: const Text('Vos réponses non envoyées seront perdues. '
                'Vous pourrez reprendre la tentative tant que le quiz n’est pas soumis.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Rester')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitter')),
            ],
          ),
        );
        if (leave == true && context.mounted) context.go('/home');
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Question ${_i + 1} / ${_qs.length}'),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(_fmt(_left),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: urgent ? EdColors.red : null)),
              ),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          LinearProgressIndicator(
              value: (_i + 1) / _qs.length,
              minHeight: 6,
              color: EdColors.red,
              backgroundColor: t.dividerColor),
          const SizedBox(height: 18),
          if (q.image != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(q.image!,
                    cacheWidth: 900,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          if (q.mediaTexte != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(q.mediaTexte!, style: const TextStyle(fontStyle: FontStyle.italic))),
          for (final link in [q.audio, q.video].whereType<String>())
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: Text(link == q.audio ? 'Écouter l’audio' : 'Voir la vidéo'),
              onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
            ),
          Text(q.texte, style: t.textTheme.titleMedium?.copyWith(height: 1.4)),
          const SizedBox(height: 14),
          if (q.isChoice)
            for (final c in q.choices)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: a.ids.contains(c.id) ? EdColors.blue.withValues(alpha: 0.1) : null,
                child: q.isMultiple
                    ? CheckboxListTile(
                        value: a.ids.contains(c.id),
                        title: Text(c.texte),
                        onChanged: (v) => setState(
                            () => v == true ? a.ids.add(c.id) : a.ids.remove(c.id)),
                      )
                    : ListTile(
                        leading: Icon(a.ids.contains(c.id)
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                        title: Text(c.texte),
                        onTap: () => setState(() {
                          a.ids
                            ..clear()
                            ..add(c.id);
                        }),
                      ),
              )
          else
            TextField(
              controller: _textCtrl,
              minLines: q.type == 'texte_libre' ? 4 : 1,
              maxLines: q.type == 'texte_libre' ? 8 : 1,
              decoration: InputDecoration(
                  hintText: q.type == 'texte_libre' ? 'Votre réponse…' : 'Complétez le texte à trous'),
              onChanged: (v) => a.text = v,
            ),
          const SizedBox(height: 18),
          Row(children: [
            if (_i > 0)
              Expanded(
                  child: OutlinedButton(
                      onPressed: _busy ? null : () => _go(_i - 1),
                      child: const Text('Précédent'))),
            if (_i > 0) const SizedBox(width: 10),
            Expanded(
              child: _i < _qs.length - 1
                  ? FilledButton(
                      onPressed: _busy ? null : () => _go(_i + 1), child: const Text('Suivant'))
                  : FilledButton(
                      onPressed: _busy ? null : _confirmAndSubmit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Terminer')),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ======================= Résultat =======================

class _ResultData {
  _ResultData(this.result, this.quiz, this.pending, this.fromCache);
  final QuizResult? result;
  final QuizDetail? quiz;
  final bool pending;
  final bool fromCache;
}

class QuizResultScreen extends StatelessWidget {
  const QuizResultScreen(this.attemptId, {super.key});
  final int attemptId;

  Future<_ResultData> _load(BuildContext context) async {
    final repo = context.read<CourseRepository>();
    final outbox = context.read<OutboxRepository>();
    final pending = await outbox.isPending('quiz-submit-$attemptId');
    QuizResult? res;
    var cached = false;
    try {
      final r = await repo.quizResult(attemptId);
      if (r.value.submitted) {
        res = r.value;
        cached = r.fromCache;
      }
    } on ApiException {
      // pas de résultat disponible (hors ligne sans cache) : état « en attente »
    }
    QuizDetail? quiz;
    final qid = res?.quizId;
    if (qid != null) {
      try {
        quiz = (await repo.quiz(qid)).value;
      } on ApiException {
        // textes des questions indisponibles
      }
    }
    return _ResultData(res, quiz, pending && res == null, cached);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Résultat'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go('/home')),
      ),
      body: AsyncView<_ResultData>(
        load: () => _load(context),
        builder: (context, d, reload) {
          if (d.result == null) {
            return EmptyState(
              icon: d.pending ? Icons.schedule_send_outlined : Icons.help_outline,
              title: d.pending ? 'Réponses en attente d’envoi' : 'Résultat indisponible',
              message: d.pending
                  ? 'Vos réponses sont enregistrées. Elles seront envoyées automatiquement '
                      'au retour de la connexion, puis le résultat s’affichera ici.'
                  : 'Impossible de récupérer le résultat pour le moment.',
              action: OutlinedButton(onPressed: reload, child: const Text('Actualiser')),
            );
          }
          final r = d.result!;
          final ok = r.reussi == true;
          final byQ = {for (final x in r.details) x.questionId: x};
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (d.fromCache) const OfflineBanner(),
            HeroCard(
              child: Column(children: [
                Icon(ok ? Icons.emoji_events_outlined : Icons.refresh_rounded,
                    color: Colors.white, size: 42),
                const SizedBox(height: 8),
                Text('${(r.score ?? 0).toStringAsFixed(0)} %',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
                Text(ok ? 'Réussi' : 'Non réussi · minimum ${r.passPct} %',
                    style: const TextStyle(color: Color(0xFFD3E2E9), fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 16),
            if (d.quiz != null)
              for (final q in d.quiz!.questions.where((q) => byQ.containsKey(q.id)))
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(
                            byQ[q.id]!.correct == null
                                ? Icons.hourglass_empty
                                : byQ[q.id]!.correct!
                                    ? Icons.check_circle
                                    : Icons.cancel,
                            color: byQ[q.id]!.correct == null
                                ? null
                                : byQ[q.id]!.correct!
                                    ? EdColors.good
                                    : EdColors.red),
                        const SizedBox(width: 10),
                        Expanded(child: Text(q.texte, style: const TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                      if (byQ[q.id]!.correct == null)
                        const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text('Correction manuelle par l’enseignant.',
                                style: TextStyle(fontSize: 12))),
                      if ((byQ[q.id]!.explication ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(byQ[q.id]!.explication!,
                              style: t.textTheme.bodySmall?.copyWith(height: 1.5)),
                        ),
                    ]),
                  ),
                ),
            const SizedBox(height: 8),
            if (d.quiz?.courseId != null)
              OutlinedButton(
                  onPressed: () => context.go('/course/${d.quiz!.courseId}'),
                  child: const Text('Retour au cours'))
            else
              OutlinedButton(onPressed: () => context.go('/home'), child: const Text('Accueil')),
          ]);
        },
      ),
    );
  }
}
