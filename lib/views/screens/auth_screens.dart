import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/auth/app_user.dart';
import '../../models/auth/auth_model.dart';
import '../../models/validation.dart';
import '../widgets/captcha_box.dart';
import '../widgets/profile_photo_picker.dart';

part 'password_reset_screens.dart';

/// Écran Sign in : e-mail et mot de passe.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _captcha = GlobalKey<CaptchaBoxState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formOk = _form.currentState!.validate();
    final captchaOk = _captcha.currentState!.ensureVerified();
    if (!formOk || !captchaOk) return;
    FocusScope.of(context).unfocus();
    final ok = await context
        .read<AuthController>()
        .signIn(email: _email.text, password: _password.text);
    // Une vérification ne sert qu'une fois.
    if (!ok && mounted) _captcha.currentState?.reset();
  }

  /// Mot de passe oublié : au retour, l'e-mail est prérempli.
  Future<void> _openForgot() async {
    final auth = context.read<AuthController>()..clearError();
    final messenger = ScaffoldMessenger.of(context);
    final email = await ForgotPasswordScreen.open(context, email: _email.text.trim());
    auth.clearError();
    if (email == null || !mounted) return;
    _email.text = email;
    _password.clear();
    _captcha.currentState?.reset();
    messenger.showSnackBar(const SnackBar(
        content: Text('Mot de passe modifié. Connectez-vous avec le nouveau.')));
  }

  Future<void> _openSignUp() async {
    final auth = context.read<AuthController>()..clearError();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SignUpScreen(),
    ));
    auth.clearError();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AuthModel>();
    return _AuthScaffold(
      title: 'Connexion',
      subtitle: 'Retrouvez vos animaux, leurs soins, repas et rappels.',
      child: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EmailField(controller: _email),
            const SizedBox(height: 14),
            PasswordField(
              controller: _password,
              label: 'Mot de passe',
              validator: (v) => (v ?? '').isEmpty ? 'Indiquez votre mot de passe' : null,
              onSubmitted: (_) => _submit(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: model.busy ? null : _openForgot,
                child: const Text('Mot de passe oublié ?'),
              ),
            ),
            CaptchaBox(key: _captcha, enabled: !model.busy),
            if (model.error != null) _ErrorBanner(model.error!),
            const SizedBox(height: 22),
            _SubmitButton(label: 'Se connecter', busy: model.busy, onPressed: _submit),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Pas encore de compte ?'),
                TextButton(
                  onPressed: model.busy ? null : _openSignUp,
                  child: const Text('Créer un compte'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Écran Sign up : nom, e-mail, mot de passe et confirmation.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _captcha = GlobalKey<CaptchaBoxState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final AuthController _auth;

  /// Photo de profil choisie (facultative).
  String? _photo;
  bool _picking = false;
  bool _signedUp = false;

  /// Rôle choisi pour le nouveau compte.
  UserRole _role = UserRole.user;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    // Inscription abandonnée : la photo copiée est supprimée.
    if (!_signedUp) _auth.discardPhoto(_photo);
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool camera) async {
    setState(() => _picking = true);
    final path = await _auth.pickPhoto(camera: camera);
    if (!mounted) return;
    if (path != null) {
      await _auth.discardPhoto(_photo);
      _photo = path;
    }
    setState(() => _picking = false);
  }

  Future<void> _removePhoto() async {
    await _auth.discardPhoto(_photo);
    setState(() => _photo = null);
  }

  String get _initials {
    final parts = _name.text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final s = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return s.isEmpty ? '?' : s;
  }

  Future<void> _submit() async {
    final formOk = _form.currentState!.validate();
    final captchaOk = _captcha.currentState!.ensureVerified();
    if (!formOk || !captchaOk) return;
    FocusScope.of(context).unfocus();
    _signedUp = await _auth.signUp(
        name: _name.text,
        email: _email.text,
        password: _password.text,
        photoPath: _photo,
        role: _role);
    if (!_signedUp && mounted) _captcha.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AuthModel>();
    return _AuthScaffold(
      title: 'Créer un compte',
      subtitle: 'Chaque compte a ses propres animaux et données.',
      showBack: true,
      child: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfilePhotoPicker(
              initials: _initials,
              path: _photo,
              busy: _picking,
              onPick: _pick,
              onRemove: _removePhoto,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              inputFormatters: [
                LengthLimitingTextInputFormatter(AppUser.maxNameLength),
              ],
              decoration: const InputDecoration(
                labelText: 'Nom',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) => InputRules.name(v, 'Le nom',
                  required: true, max: AppUser.maxNameLength),
            ),
            const SizedBox(height: 14),
            _EmailField(controller: _email),
            const SizedBox(height: 14),
            PasswordField(
              controller: _password,
              label: 'Mot de passe',
              helper: '8 caractères minimum, dont une lettre et un chiffre',
              newPassword: true,
              validator: InputRules.password,
            ),
            const SizedBox(height: 14),
            PasswordField(
              controller: _confirm,
              label: 'Confirmer le mot de passe',
              newPassword: true,
              validator: (v) => v != _password.text
                  ? 'Les mots de passe ne correspondent pas'
                  : null,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 18),
            const Text('Rôle', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<UserRole>(
              segments: const [
                ButtonSegment(
                    value: UserRole.user,
                    label: Text('Utilisateur'),
                    icon: Icon(Icons.person_rounded)),
                ButtonSegment(
                    value: UserRole.admin,
                    label: Text('Administrateur'),
                    icon: Icon(Icons.admin_panel_settings_rounded)),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            const SizedBox(height: 18),
            CaptchaBox(key: _captcha, enabled: !model.busy),
            if (model.error != null) _ErrorBanner(model.error!),
            const SizedBox(height: 22),
            _SubmitButton(
                label: 'Créer mon compte', busy: model.busy, onPressed: _submit),
            const SizedBox(height: 12),
            Text(
              'Le premier compte créé sur ce téléphone est toujours administrateur.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- Composants

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: showBack
          ? AppBar(backgroundColor: Colors.transparent, elevation: 0)
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.pets_rounded,
                          size: 38, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Smart Pet',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.primary, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 18),
                  Text(title,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailField extends StatelessWidget {
  const _EmailField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        autofillHints: const [AutofillHints.email],
        inputFormatters: [
          LengthLimitingTextInputFormatter(100),
          FilteringTextInputFormatter.deny(RegExp(r'\s')),
        ],
        decoration: const InputDecoration(
          labelText: 'E-mail',
          hintText: 'nom@exemple.com',
          prefixIcon: Icon(Icons.alternate_email_rounded),
        ),
        validator: InputRules.email,
      );
}

/// Champ mot de passe avec bouton Afficher / Masquer.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.helper,
    this.newPassword = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool newPassword;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _hidden,
        enableSuggestions: false,
        autocorrect: false,
        autofillHints: [
          widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
        ],
        inputFormatters: [
          LengthLimitingTextInputFormatter(InputRules.maxPasswordLength),
        ],
        textInputAction:
            widget.onSubmitted == null ? TextInputAction.next : TextInputAction.done,
        onFieldSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helper,
          helperMaxLines: 2,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: _hidden ? 'Afficher' : 'Masquer',
            icon: Icon(_hidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
        validator: widget.validator,
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: AppColors.danger, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(52),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
