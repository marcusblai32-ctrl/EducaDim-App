import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/common.dart';
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
  bool _busy = false, _hide = true;
  String? _error;
  String? _diag;
  bool _slow = false;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _slow = false;
    });
    final slow = Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _busy) setState(() => _slow = true);
    });
    try {
      await context.read<AuthController>().login(_id.text, _pw.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      slow.ignore();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _diagnose() async {
    setState(() => _diag = 'Test en cours… (jusqu’à 1 minute)');
    final r = await context.read<AuthController>().diagnose();
    if (mounted) setState(() => _diag = r);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Image.asset('assets/logo.png',
                              height: 96, semanticLabel: 'Logo EducaDim'),
                        ),
                        const SizedBox(height: 14),
                        const PageHeader('Bon retour', 'Connectez-vous',
                            subtitle:
                                'Accédez à vos formations et reprenez votre apprentissage.'),
                        TextFormField(
                          controller: _id,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username],
                          decoration:
                              const InputDecoration(labelText: 'E-mail ou identifiant (user_id)'),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _pw,
                          obscureText: _hide,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            suffixIcon: IconButton(
                              tooltip: _hide ? 'Afficher' : 'Masquer',
                              icon: Icon(_hide
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _hide = !_hide),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Champ requis' : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: const TextStyle(
                                  color: EdColors.red, fontWeight: FontWeight.w700)),
                        ],
                        if (_busy && _slow) ...[
                          const SizedBox(height: 12),
                          const Text(
                              'Le serveur se réveille, cela peut prendre jusqu’à 1 minute…'),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Se connecter'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => launchUrl(
                            Uri.parse(ApiConfig.signupWebUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text('Créer un compte (site EducaDim)'),
                        ),
                        TextButton(
                          onPressed: _diagnose,
                          child: const Text('Tester la connexion au serveur'),
                        ),
                        if (_diag != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_diag!, style: const TextStyle(height: 1.4)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
