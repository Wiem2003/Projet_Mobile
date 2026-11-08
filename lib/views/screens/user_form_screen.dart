import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/admin_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/auth/app_user.dart';
import '../../models/validation.dart';
import '../widgets/profile_photo_picker.dart';
import 'auth_screens.dart';

/// Administration : créer un compte (utilisateur ou administrateur) ou
/// modifier un compte existant (nom, e-mail, rôle, statut, photo, nouveau
/// mot de passe).
class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key, this.user});

  /// Compte modifié ; `null` pour une création.
  final AppUser? user;

  static Future<AppUser?> open(BuildContext context, {AppUser? user}) => Navigator.of(context)
      .push<AppUser>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => UserFormScreen(user: user)));

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _form = GlobalKey<FormState>();
  late final AdminController _admin;
  late final TextEditingController _name;
  late final TextEditingController _email;
  final _password = TextEditingController();
  late UserRole _role;
  late bool _active;
  String? _photo;

  /// Photos choisies pendant la saisie (supprimées si non retenues).
  final _picked = <String>[];
  bool _picking = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    _admin = context.read<AdminController>();
    final u = widget.user;
    _name = TextEditingController(text: u?.name ?? '')..addListener(() => setState(() {}));
    _email = TextEditingController(text: u?.email ?? '');
    _role = u?.role ?? UserRole.user;
    _active = u?.active ?? true;
    _photo = u?.photoPath;
  }

  @override
  void dispose() {
    for (final p in _picked) {
      if (p != _photo || !_saved) _admin.discardPhoto(p);
    }
    for (final c in [_name, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _saved = false;

  Future<void> _pick(bool camera) async {
    setState(() => _picking = true);
    final path = await _admin.pickPhoto(camera: camera);
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (path != null) {
        _picked.add(path);
        _photo = path;
      }
    });
  }

  String get _initials {
    final parts = _name.text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final s = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return s.isEmpty ? '?' : s;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = _isEdit
          ? await _admin.update(widget.user!,
              name: _name.text,
              email: _email.text,
              role: _role,
              active: _active,
              photoPath: _photo,
              newPassword: _password.text)
          : await _admin.create(
              name: _name.text,
              email: _email.text,
              password: _password.text,
              role: _role,
              photoPath: _photo);
      _saved = true;
      if (mounted) Navigator.pop(context, saved);
    } on RecordException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Modifier le compte' : 'Nouveau compte'),
        leading: IconButton(
          tooltip: 'Fermer',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            ProfilePhotoPicker(
              initials: _initials,
              path: _photo,
              busy: _picking,
              onPick: _pick,
              onRemove: () => setState(() => _photo = null),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(AppUser.maxNameLength)],
              decoration: const InputDecoration(
                  labelText: 'Nom', prefixIcon: Icon(Icons.person_outline_rounded)),
              validator: (v) =>
                  InputRules.name(v, 'Le nom', required: true, max: AppUser.maxNameLength),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              inputFormatters: [
                LengthLimitingTextInputFormatter(100),
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              decoration: const InputDecoration(
                  labelText: 'E-mail', prefixIcon: Icon(Icons.alternate_email_rounded)),
              validator: InputRules.email,
            ),
            const SizedBox(height: 14),
            PasswordField(
              controller: _password,
              label: _isEdit ? 'Nouveau mot de passe' : 'Mot de passe',
              helper: _isEdit
                  ? 'Laisser vide pour garder le mot de passe actuel'
                  : '8 caractères minimum, dont une lettre et un chiffre',
              newPassword: true,
              validator: (v) =>
                  _isEdit && (v ?? '').isEmpty ? null : InputRules.password(v),
            ),
            const SizedBox(height: 18),
            const Text('Rôle', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<UserRole>(
              segments: [
                for (final r in UserRole.values) ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            if (_isEdit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Compte actif'),
                subtitle: const Text('Un compte désactivé ne peut plus se connecter'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.reminder, minimumSize: const Size.fromHeight(52)),
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded),
            label: Text(_isEdit ? 'Enregistrer' : 'Créer le compte'),
            onPressed: _saving ? null : _save,
          ),
        ),
      ),
    );
  }
}
