import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/auth/app_user.dart';
import '../../models/auth/auth_model.dart';
import '../../models/validation.dart';
import '../formatters.dart';
import 'admin_screen.dart';
import 'auth_screens.dart';
import '../widgets/profile_photo_picker.dart';

/// Avatar d'un compte (initiales), couleur selon le rôle.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 22});

  final AppUser user;
  final double radius;

  @override
  Widget build(BuildContext context) => ProfilePhoto(
        initials: user.initials,
        path: user.photoPath,
        size: radius * 2,
        color: user.isAdmin ? AppColors.reminderDeep : AppColors.primary,
      );
}

/// Badge « Administrateur » / « Utilisateur ».
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final color = role == UserRole.admin ? AppColors.reminder : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(role.label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Mon compte : profil, mot de passe, administration, déconnexion.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthModel>().user;
    if (user == null) return const Scaffold();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  UserAvatar(user: user, radius: 30),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(user.email,
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        RoleBadge(role: user.role),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (user.createdAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text('Compte créé : ${Fmt.long(user.createdAt!)}',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.add_a_photo_outlined),
                  title: const Text('Changer la photo'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _changePhoto(context, user),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Modifier mon nom'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editName(context, user),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_reset_rounded),
                  title: const Text('Changer le mot de passe'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _changePassword(context),
                ),
                if (user.isAdmin) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined,
                        color: AppColors.reminder),
                    title: const Text('Administration'),
                    subtitle: const Text('Comptes, rôles et statistiques'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => AdminScreen.open(context),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Se déconnecter'),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
    );
  }

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const AccountScreen()));

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
            'Vos données restent enregistrées sur le téléphone. Les rappels '
            'de ce compte ne seront plus notifiés jusqu\'à la prochaine connexion.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AuthController>().signOut();
    }
  }

  Future<void> _changePhoto(BuildContext context, AppUser user) async {
    final controller = context.read<AuthController>();
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Appareil photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (user.photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                title: const Text('Retirer la photo'),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    String? path;
    if (choice != 'remove') {
      path = await controller.pickPhoto(camera: choice == 'camera');
      if (path == null) return;
    }
    final error = await controller.setPhoto(path);
    messenger.showSnackBar(SnackBar(
        content: Text(error ?? (path == null ? 'Photo retirée' : 'Photo modifiée'))));
  }

  Future<void> _editName(BuildContext context, AppUser user) async {
    final controller = context.read<AuthController>();
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FormDialog(
        title: 'Modifier mon nom',
        fields: (form) => [
          TextFormField(
            controller: form.text('name', user.name),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(AppUser.maxNameLength)],
            decoration: const InputDecoration(labelText: 'Nom'),
            validator: (v) => InputRules.name(v, 'Le nom',
                required: true, max: AppUser.maxNameLength),
          ),
        ],
        onSave: (values) => controller.updateName(values['name']!),
      ),
    );
    if (saved == true) messenger.showSnackBar(const SnackBar(content: Text('Nom modifié')));
  }

  Future<void> _changePassword(BuildContext context) async {
    final controller = context.read<AuthController>();
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FormDialog(
        title: 'Changer le mot de passe',
        fields: (form) => [
          PasswordField(
            controller: form.text('current'),
            label: 'Mot de passe actuel',
            validator: (v) => (v ?? '').isEmpty ? 'Obligatoire' : null,
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: form.text('next'),
            label: 'Nouveau mot de passe',
            helper: '8 caractères minimum, dont une lettre et un chiffre',
            newPassword: true,
            validator: InputRules.password,
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: form.text('confirm'),
            label: 'Confirmer',
            newPassword: true,
            validator: (v) => v != form.text('next').text
                ? 'Les mots de passe ne correspondent pas'
                : null,
          ),
        ],
        onSave: (values) => controller.changePassword(
            current: values['current']!, next: values['next']!),
      ),
    );
    if (saved == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Mot de passe modifié')));
    }
  }
}

/// Champs texte d'une boîte de dialogue, créés à la demande.
class _DialogFields {
  final _controllers = <String, TextEditingController>{};

  TextEditingController text(String key, [String initial = '']) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: initial));

  Map<String, String> get values => {
        for (final e in _controllers.entries) e.key: e.value.text,
      };

  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
  }
}

/// Boîte de dialogue avec formulaire ; [onSave] renvoie l'erreur à
/// afficher, ou `null` si c'est enregistré (la boîte se ferme).
class _FormDialog extends StatefulWidget {
  const _FormDialog({required this.title, required this.fields, required this.onSave});

  final String title;
  final List<Widget> Function(_DialogFields form) fields;
  final Future<String?> Function(Map<String, String> values) onSave;

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final _key = GlobalKey<FormState>();
  final _fields = _DialogFields();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    final error = await widget.onSave(_fields.values);
    if (!mounted) return;
    if (error == null) return Navigator.pop(context, true);
    setState(() {
      _error = error;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _key,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...widget.fields(_fields),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
        ],
      );
}
