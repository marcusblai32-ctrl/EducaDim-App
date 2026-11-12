import 'package:flutter/material.dart' hide Text;
import '../../core/audio/sfx.dart';
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import 'review_service.dart';

/// Feuille d'évaluation : étoiles + commentaire. `reminder` = ouverture automatique
/// (bouton « Plus tard » ) ; sinon ouverte depuis le profil.
Future<void> showReviewSheet(BuildContext context, {bool reminder = false}) {
  final svc = context.read<ReviewService>();
  if (reminder) svc.markPrompted();
  return showModalBottomSheet<void>(sheetAnimationStyle: AnimationStyle.noAnimation, 
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider.value(value: svc, child: _ReviewSheet(reminder: reminder)),
  );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.reminder});
  final bool reminder;
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late int _stars = context.read<ReviewService>().stars ?? 0;
  late final _c = TextEditingController(text: context.read<ReviewService>().comment);
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, SnackBar(content: Text('Choisissez une note de 1 à 5.')));
      return;
    }
    setState(() => _busy = true);
    final msg = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await context.read<ReviewService>().submit(_stars, _c.text);
      nav.pop();
      Sfx.complete();
      msg.showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, SnackBar(content: Text('Merci pour votre avis !')));
    } on ApiException catch (e) {
      msg.showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Votre avis compte', style: t.textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
              widget.reminder
                  ? 'Vous n’avez pas encore donné votre avis sur EducaDim. Cela nous aide à améliorer l’application.'
                  : 'Notez votre expérience avec EducaDim.',
              style: t.textTheme.bodyMedium?.copyWith(height: 1.5)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: tr('$i'),
                iconSize: 38,
                onPressed: () => setState(() => _stars = i),
                icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: i <= _stars ? const Color(0xFFF5A623) : t.dividerColor),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _c,
            minLines: 3,
            maxLines: 5,
            maxLength: 1500,
            decoration: InputDecoration(labelText: tr('Votre commentaire (facultatif)')),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: _busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Envoyer mon avis'),
          ),
          if (widget.reminder)
            Center(
              child: TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context), child: Text('Plus tard')),
            ),
          Text('Votre avis sera vérifié avant publication.',
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85))),
        ]),
      ),
    );
  }
}
