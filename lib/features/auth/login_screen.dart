import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/api_config.dart';
import '../../core/i18n/text.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/language_button.dart';
import 'auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false, _hide = true, _slow = false, _needCode = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _slow = false;
    });
    final slow = Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _busy) setState(() => _slow = true);
    });
    try {
      final auth = context.read<AuthController>();
      if (_needCode) {
        await auth.verify2fa(_code.text);
      } else if (await auth.login(_id.text, _pw.text)) {
        if (mounted) setState(() => _needCode = true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          if (_needCode && context.read<AuthController>().pending2fa == null) _needCode = false;
        });
      }
    } finally {
      slow.ignore();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthController>().resend2fa();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          // ---- En-tête de marque ----
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: EdColors.hero,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(children: [
                  const Align(alignment: Alignment.centerRight, child: LanguageButton(onDark: true)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Image.asset('assets/logo.png', height: 72),
                  ),
                  const SizedBox(height: 22),
                  const Text('Bon retour !',
                      style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Connectez-vous pour reprendre votre apprentissage.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFDDE2FF), height: 1.4)),
                ]),
              ),
            ),
          ),
          // ---- Formulaire ----
          Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_needCode) ...[
                    Text(
                        tr('Un code de vérification a été envoyé à {t}.',
                            {'t': (context.read<AuthController>().pending2fa?['target'] ?? '').toString()}),
                        style: t.textTheme.bodyMedium),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      decoration: InputDecoration(
                        labelText: tr('Code de vérification'),
                        prefixIcon: const Icon(Icons.shield_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().length != 6) ? tr('Entrez le code à 6 chiffres') : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    Row(children: [
                      TextButton(onPressed: _busy ? null : _resend, child: Text(tr('Renvoyer le code'))),
                      TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  context.read<AuthController>().cancel2fa();
                                  setState(() {
                                    _needCode = false;
                                    _code.clear();
                                    _error = null;
                                  });
                                },
                          child: Text(tr('Retour'))),
                    ]),
                  ] else ...[
                  TextFormField(
                    controller: _id,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: tr('E-mail ou identifiant'),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? tr('Champ requis') : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pw,
                    obscureText: _hide,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: tr('Mot de passe'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _hide ? tr('Afficher') : tr('Masquer'),
                        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? tr('Champ requis') : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: EdColors.red.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.error_outline_rounded, color: EdColors.red, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(_error!,
                                style: const TextStyle(color: EdColors.red, fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  ],
                  if (_busy && _slow) ...[
                    const SizedBox(height: 12),
                    Text('Connexion en cours… cela peut prendre un moment.',
                        style: t.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(_needCode ? tr('Vérifier') : tr('Se connecter')),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => launchUrl(Uri.parse(ApiConfig.signupWebUrl),
                          mode: LaunchMode.externalApplication),
                      child: const Text('Créer un compte'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
