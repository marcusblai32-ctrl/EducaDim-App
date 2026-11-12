import 'package:flutter/material.dart' hide Text;
import '../../core/audio/sfx.dart';
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import 'course_repository.dart';
import 'course_widgets.dart';
import 'models.dart';

/// Révision de flashcards d'un MODULE (ou, pour les anciens contenus, du cours).
/// Aucune animation : la carte se retourne instantanément. Les résultats
/// « je sais / à revoir » ne servent qu'à la séance en cours.
class FlashcardsScreen extends StatelessWidget {
  const FlashcardsScreen({super.key, this.moduleId, this.courseId, this.title});
  final int? moduleId;
  final int? courseId;
  final String? title;

  Future<Loaded<List<Flashcard>>> _load(CourseRepository repo) async {
    try {
      if (moduleId != null) return await repo.moduleFlashcards(moduleId!);
      final r = await repo.courseFlashcards(courseId!);
      return Loaded(r.value.general, fromCache: r.fromCache);
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        throw ApiException(tr('Cette fonctionnalité n’est pas disponible pour le moment.'));
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CourseRepository>();
    return Scaffold(
      appBar: AppBar(title: Text(title ?? tr('Flashcards'), overflow: TextOverflow.ellipsis)),
      body: AsyncView<Loaded<List<Flashcard>>>(
        load: () => _load(repo),
        builder: (context, r, _) {
          if (r.value.isEmpty) {
            return const EmptyState(
                icon: Icons.style_outlined,
                title: 'Aucune flashcard',
                message: 'Il n’y a pas encore de flashcards ici.');
          }
          return _Deck(r.value, r.fromCache);
        },
      ),
    );
  }
}

class _Deck extends StatefulWidget {
  const _Deck(this.cards, this.fromCache);
  final List<Flashcard> cards;
  final bool fromCache;
  @override
  State<_Deck> createState() => _DeckState();
}

class _DeckState extends State<_Deck> {
  late List<Flashcard> _queue = List.of(widget.cards);
  bool _flipped = false;
  int _known = 0;
  final Set<int> _review = {};

  void _answer(bool knew) {
    if (_queue.length == 1 && knew) {
      Sfx.success(); // dernière carte maîtrisée : séance terminée
    } else {
      knew ? Sfx.complete() : Sfx.fail();
    }
    setState(() {
      final c = _queue.removeAt(0);
      if (knew) {
        _known++;
      } else {
        _review.add(c.id);
        _queue.add(c); // revient à la fin de la pile
      }
      _flipped = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (_queue.isEmpty) {
      return EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'Séance terminée',
        message: _review.isEmpty
            ? tr('{n} cartes maîtrisées.', {'n': widget.cards.length})
            : tr('{n} cartes maîtrisées · {r} à revoir.', {'n': widget.cards.length, 'r': _review.length}),
        action: OutlinedButton(
          onPressed: () => setState(() {
            _queue = List.of(widget.cards);
            _known = 0;
            _review.clear();
          }),
          child: const Text('Recommencer'),
        ),
      );
    }
    final c = _queue.first;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (widget.fromCache) const OfflineBanner(),
      Text(tr('Restantes : {n} · Sues : {k}', {'n': _queue.length, 'k': _known}),
          style: t.textTheme.bodySmall),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () => setState(() => _flipped = !_flipped),
        child: Container(
          constraints: const BoxConstraints(minHeight: 260),
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: _flipped
                ? const LinearGradient(colors: [EdColors.red, Color(0xFFA6151C)])
                : EdColors.hero,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Eyebrow(_flipped ? 'Réponse' : 'Question', color: Colors.white70),
            const SizedBox(height: 16),
            Text(_flipped ? c.reponse : c.question,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700, height: 1.4)),
            const SizedBox(height: 18),
            if (!_flipped)
              const Text('Touchez pour voir la réponse',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      if (_flipped)
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => _answer(false), child: const Text('À revoir'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: () => _answer(true), child: const Text('Je sais'))),
        ]),
    ]);
  }
}
