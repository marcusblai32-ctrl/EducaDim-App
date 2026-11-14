import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/i18n/text.dart';
import '../auth/auth_controller.dart';

const String _kNextPrompt = 'phone_prompt_next_ms';
const Duration _kEvery = Duration(days: 7);

/// Rappel doux, de temps en temps (comme sur le site) : si le compte n'a pas encore de numéro de téléphone,
/// on le demande. « Plus tard » : on redemande dans 7 jours. Ne fait rien hors connexion ou si le numéro existe.
void maybeAskPhone(BuildContext context) {
  unawaited(_ask(context));
}

Future<void> _ask(BuildContext context) async {
  final auth = context.read<AuthController>();
  if (auth.user == null || auth.hasPhone) return;
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now < (prefs.getInt(_kNextPrompt) ?? 0)) return;
  // petite pause : l'écran d'accueil a le temps de s'afficher avant la question
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  if (!context.mounted || auth.hasPhone) return;
  await prefs.setInt(_kNextPrompt, now + _kEvery.inMilliseconds);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _PhoneDialog(auth: auth),
  );
}

class _PhoneDialog extends StatefulWidget {
  const _PhoneDialog({required this.auth});
  final AuthController auth;

  @override
  State<_PhoneDialog> createState() => _PhoneDialogState();
}

class _PhoneDialogState extends State<_PhoneDialog> {
  final TextEditingController _number = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _number.text.trim();
    if (value.isEmpty) {
      setState(() => _error = tr('Écrivez votre numéro de téléphone.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.auth.savePhone(value);
    if (!mounted) return;
    if (error == null) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(const SnackBar(content: Text('Numéro enregistré. Merci !')));
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.phone_android_rounded),
      title: const Text('Ajoutez votre numéro de téléphone'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nous vous préviendrons par SMS : inscription confirmée, paiement vérifié, abonnement.'),
          const SizedBox(height: 14),
          TextField(
            controller: _number,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: tr('Numéro de téléphone'),
              hintText: '+509 37 12 3456',
              helperText: tr('Pour un numéro haïtien, les 8 chiffres suffisent.'),
              helperMaxLines: 2,
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: t.colorScheme.onPrimary),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
