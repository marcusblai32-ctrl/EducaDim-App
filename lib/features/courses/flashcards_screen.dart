import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import 'course_repository.dart';
import 'course_widgets.dart';
import 'models.dart';

/// Révision de flashcards. Les résultats « je sais / à revoir » restent sur
/// l'appareil pendant la séance (le backend n'enregistre pas ce suivi).
class FlashcardsScreen extends StatelessWidget {
  const FlashcardsScreen(this.courseId, {super.key});
  final int courseId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CourseRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Flashcards')),
      body: AsyncView<Loaded<List<Flashcard>>>(
        load: () async {
          try {
            return await repo.flashcards(courseId);
          } on ApiException catch (e) {
            if (e.statusCode == 404) {
              throw ApiException(
                  'Les flashcards ne sont pas encore disponibles sur le serveur '
                  '(mise à jour du backend nécessaire).');
            }
            rethrow;
          }
        },
        builder: (context, r, _) {
          if (r.value.isEmpty) {
            return const EmptyState(
                icon: Icons.style_outlined,
                title: 'Aucune flashcard',
                message: 'Ce cours ne contient pas encore de flashcards.');
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
        message: '${widget.cards.length} cartes maîtrisées'
            '${_review.isEmpty ? '' : ' · ${_review.length} revue(s) nécessaire(s)'}.',
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
      Text('Restantes : ${_queue.length} · Sues : $_known',
          style: t.textTheme.bodySmall),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () => setState(() => _flipped = !_flipped),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 240),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: _flipped
                  ? const [EdColors.blue, EdColors.turquoise]
                  : const [EdColors.navy, EdColors.navyLight],
            ),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Eyebrow(_flipped ? 'Réponse' : 'Question', color: Colors.white70),
            const SizedBox(height: 14),
            Text(_flipped ? c.reponse : c.question,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1.4)),
            const SizedBox(height: 16),
            if (!_flipped)
              const Text('Touchez pour voir la réponse',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      if (_flipped)
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => _answer(false), child: const Text('À revoir'))),
          const SizedBox(width: 10),
          Expanded(
              child: FilledButton(
                  onPressed: () => _answer(true), child: const Text('Je sais'))),
        ]),
    ]);
  }
}
