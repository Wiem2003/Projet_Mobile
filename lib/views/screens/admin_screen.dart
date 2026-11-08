import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/admin_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/auth/admin_model.dart';
import '../../models/auth/app_user.dart';
import '../../models/validation.dart';
import '../formatters.dart';
import 'account_screen.dart';
import 'user_form_screen.dart';

/// Administration (rôle admin) : chiffres de l'app et gestion des comptes.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  static const color = AppColors.reminder;

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const AdminScreen()));

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AdminController>().load();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AdminModel>();
    final controller = context.read<AdminController>();
    final s = model.stats;
    final users = model.visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        backgroundColor: AdminScreen.color,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AdminScreen.color,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Ajouter un compte'),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final created = await UserFormScreen.open(context);
          if (created != null) {
            messenger.showSnackBar(SnackBar(
                content: Text('Compte ${created.role.label.toLowerCase()} « ${created.name} » créé')));
          }
        },
      ),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Stat('Comptes', s.users, Icons.group_rounded, AdminScreen.color),
                _Stat('Admins', s.admins, Icons.admin_panel_settings_rounded,
                    AppColors.reminderDeep),
                _Stat('Désactivés', s.disabled, Icons.block_rounded, AppColors.danger),
                _Stat('Animaux', s.pets, Icons.pets_rounded, AppColors.pet),
                _Stat('Soins', s.healthRecords, Icons.medical_services_rounded,
                    AppColors.health),
                _Stat('Repas', s.feedingRecords, Icons.restaurant_rounded,
                    AppColors.feeding),
                _Stat('Activités', s.activities, Icons.directions_run_rounded,
                    AppColors.activity),
                _Stat('Rappels', s.reminders, Icons.notifications_rounded,
                    AppColors.primary),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: controller.setQuery,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              decoration: const InputDecoration(
                hintText: 'Rechercher (nom, e-mail)',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final f in UserFilter.values)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: model.filter == f,
                    onSelected: (_) => controller.setFilter(f),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (model.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(model.error!, style: const TextStyle(color: AppColors.danger)),
              ),
            if (model.loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (users.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Aucun compte ne correspond.')),
              )
            else
              for (final u in users)
                _UserCard(summary: u, isMe: u.user.id == controller.adminId),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, this.color);

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 104,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text('$value',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

enum _Action { edit, promote, demote, disable, enable, delete }

class _UserCard extends StatelessWidget {
  const _UserCard({required this.summary, required this.isMe});

  final UserSummary summary;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final u = summary.user;
    final scheme = Theme.of(context).colorScheme;
    final last = u.lastLoginAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Opacity(opacity: u.active ? 1 : 0.45, child: UserAvatar(user: u)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isMe ? '${u.name} (vous)' : u.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(u.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      RoleBadge(role: u.role),
                      if (!u.active)
                        const Text('Désactivé',
                            style: TextStyle(
                                color: AppColors.danger,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      Text(
                        '${summary.pets} ${summary.pets > 1 ? 'animaux' : 'animal'} · '
                        '${summary.reminders} rappel${summary.reminders > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  if (last != null)
                    Text('Dernière connexion : ${Fmt.dateTime(last)}',
                        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (!isMe)
              PopupMenuButton<_Action>(
                tooltip: 'Actions',
                onSelected: (a) => _run(context, a),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: _Action.edit, child: Text('Modifier')),
                  if (u.isAdmin)
                    const PopupMenuItem(
                        value: _Action.demote, child: Text('Retirer le rôle admin'))
                  else
                    const PopupMenuItem(
                        value: _Action.promote, child: Text('Nommer administrateur')),
                  if (u.active)
                    const PopupMenuItem(value: _Action.disable, child: Text('Désactiver'))
                  else
                    const PopupMenuItem(value: _Action.enable, child: Text('Réactiver')),
                  const PopupMenuItem(
                    value: _Action.delete,
                    child: Text('Supprimer', style: TextStyle(color: AppColors.danger)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(BuildContext context, _Action action) async {
    final controller = context.read<AdminController>();
    final messenger = ScaffoldMessenger.of(context);
    final u = summary.user;
    if (action == _Action.edit) {
      final saved = await UserFormScreen.open(context, user: u);
      if (saved != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Compte de ${saved.name} modifié')));
      }
      return;
    }
    if (action == _Action.delete && !await _confirmDelete(context)) return;
    try {
      final message = switch (action) {
        _Action.promote => (await controller.setRole(u, UserRole.admin),
            '${u.name} est maintenant administrateur').$2,
        _Action.demote =>
          (await controller.setRole(u, UserRole.user), '${u.name} est maintenant utilisateur').$2,
        _Action.disable =>
          (await controller.setActive(u, false), 'Compte de ${u.name} désactivé').$2,
        _Action.enable =>
          (await controller.setActive(u, true), 'Compte de ${u.name} réactivé').$2,
        _Action.delete => await controller.delete(u).then((_) => 'Compte de ${u.name} supprimé'),
        _Action.edit => '',
      };
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } on RecordException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final u = summary.user;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Supprimer le compte de ${u.name} ?'),
            content: Text(
                'Ses ${summary.pets} animal(aux) et toutes leurs données (santé, '
                'repas, activités, rappels) seront supprimés. Cette action est '
                'définitive.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler')),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Supprimer')),
            ],
          ),
        ) ??
        false;
  }
}
