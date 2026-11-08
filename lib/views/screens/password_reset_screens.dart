part of 'auth_screens.dart';

/// Mot de passe oublié, étape 1 : l'e-mail du compte, puis envoi d'un code
/// à 6 chiffres. Renvoie l'e-mail quand le mot de passe a été changé.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});

  final String email;

  static Future<String?> open(BuildContext context, {String email = ''}) =>
      Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => ForgotPasswordScreen(email: email)));

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _captcha = GlobalKey<CaptchaBoxState>();
  late final _email = TextEditingController(text: widget.email);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final formOk = _form.currentState!.validate();
    final captchaOk = _captcha.currentState!.ensureVerified();
    if (!formOk || !captchaOk) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    final result = await auth.requestPasswordReset(_email.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      _captcha.currentState?.reset();
      return setState(() => _error = result.error);
    }
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ResetPasswordScreen(email: _email.text.trim(), demoCode: result.demoCode),
    ));
    if (!mounted) return;
    if (changed == true) {
      Navigator.pop(context, _email.text.trim().toLowerCase());
    } else {
      _captcha.currentState?.reset();
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: 'Mot de passe oublié',
        subtitle: 'Indiquez l\'e-mail de votre compte : nous vous envoyons un code à '
            '6 chiffres pour choisir un nouveau mot de passe.',
        showBack: true,
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EmailField(controller: _email),
              const SizedBox(height: 14),
              CaptchaBox(key: _captcha, enabled: !_busy),
              if (_error != null) _ErrorBanner(_error!),
              const SizedBox(height: 22),
              _SubmitButton(label: 'Envoyer le code', busy: _busy, onPressed: _send),
            ],
          ),
        ),
      );
}

/// Mot de passe oublié, étape 2 : le code reçu par e-mail et le nouveau mot
/// de passe. Renvoie `true` quand il est changé.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.email, this.demoCode});

  final String email;

  /// Code affiché quand l'envoi d'e-mails n'est pas configuré (debug).
  final String? demoCode;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final AuthController _auth = context.read<AuthController>();
  late String? _demoCode = widget.demoCode;
  Timer? _ticker;
  Duration _wait = Duration.zero;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in [_code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Compte à rebours du bouton « Renvoyer le code ».
  void _startCountdown() {
    _ticker?.cancel();
    _wait = _auth.resendIn(widget.email);
    if (_wait == Duration.zero) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait = _auth.resendIn(widget.email));
      if (_wait == Duration.zero) t.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final result = await _auth.requestPasswordReset(widget.email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _demoCode = result.demoCode ?? _demoCode;
        _info = 'Nouveau code envoyé. L\'ancien ne fonctionne plus.';
        _code.clear();
      } else {
        _error = result.error;
      }
    });
    _startCountdown();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final error = await _auth.resetPassword(
        email: widget.email, code: _code.text, newPassword: _password.text);
    if (!mounted) return;
    if (error == null) return Navigator.pop(context, true);
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13);
    return _AuthScaffold(
      title: 'Nouveau mot de passe',
      subtitle: 'Si un compte correspond à ${widget.email}, un code à 6 chiffres vient '
          'd\'y être envoyé. Il est valable 15 minutes.',
      showBack: true,
      child: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_demoCode != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Mode démo : l\'envoi d\'e-mails n\'est pas configuré (env.json). '
                  'Code : $_demoCode',
                  style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w600),
                ),
              ),
            TextFormField(
              controller: _code,
              autofocus: _demoCode == null,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: const TextStyle(fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'Code reçu par e-mail',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
              validator: (v) => (v ?? '').length != 6 ? 'Le code contient 6 chiffres' : null,
            ),
            const SizedBox(height: 14),
            PasswordField(
              controller: _password,
              label: 'Nouveau mot de passe',
              helper: '8 caractères minimum, dont une lettre et un chiffre',
              newPassword: true,
              validator: InputRules.password,
            ),
            const SizedBox(height: 14),
            PasswordField(
              controller: _confirm,
              label: 'Confirmer le mot de passe',
              newPassword: true,
              validator: (v) =>
                  v != _password.text ? 'Les mots de passe ne correspondent pas' : null,
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) _ErrorBanner(_error!),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_info!,
                    style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 22),
            _SubmitButton(label: 'Changer le mot de passe', busy: _busy, onPressed: _save),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.forward_to_inbox_rounded),
                label: Text(_wait == Duration.zero
                    ? 'Renvoyer le code'
                    : 'Renvoyer le code (${(_wait.inMilliseconds / 1000).ceil()} s)'),
                onPressed: _busy || _wait > Duration.zero ? null : _resend,
              ),
            ),
            Text('Pensez à regarder dans les spams si l\'e-mail n\'arrive pas.',
                textAlign: TextAlign.center, style: muted),
          ],
        ),
      ),
    );
  }
}
