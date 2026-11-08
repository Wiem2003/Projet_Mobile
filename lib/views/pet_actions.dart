import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/pet_form_controller.dart';
import '../controllers/pets_controller.dart';
import '../core/theme/app_colors.dart';
import '../models/pet.dart';
import '../models/pet_form_model.dart';
import '../models/validation.dart';
import 'screens/pet_detail_screen.dart';
import 'screens/pet_form_screen.dart';
import 'screens/pets_screen.dart';

/// Actions du module Animaux et leurs retours visuels.
abstract final class PetActions {
  static PetsController _controller(BuildContext context) =>
      context.read<PetsController>();

  static Future<void> openList(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const PetsScreen()));

  static Future<void> openDetail(BuildContext context, Pet pet) =>
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PetDetailScreen(petId: pet.id!)));

  /// Renvoie l'animal enregistré (null si le formulaire est fermé).
  static Future<Pet?> openForm(BuildContext context, {Pet? pet}) {
    final controller = _controller(context);
    return Navigator.of(context).push<Pet>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Provider<PetFormController>(
        create: (_) => PetFormController(controller, initial: pet),
        dispose: (_, c) => c.dispose(),
        child: Builder(
          builder: (context) => ChangeNotifierProvider<PetFormModel>.value(
            value: context.read<PetFormController>().model,
            child: const PetFormScreen(),
          ),
        ),
      ),
    ));
  }

  /// Confirme en listant ce qui sera supprimé dans les autres modules.
  static Future<bool> delete(BuildContext context, Pet pet) async {
    final controller = _controller(context);
    final messenger = ScaffoldMessenger.of(context);
    final linked = await controller.linkedRecords(pet);
    if (!context.mounted) return false;
    final parts = [
      if (linked.health > 0) '${linked.health} dossier(s) de santé',
      if (linked.feeding > 0) '${linked.feeding} repas',
      if (linked.activities > 0) '${linked.activities} activité(s)',
      if (linked.reminders > 0) '${linked.reminders} rappel(s)',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        title: Text('Supprimer ${pet.name} ?'),
        content: Text(parts.isEmpty
            ? 'La fiche de ${pet.name} sera définitivement supprimée.'
            : 'La fiche de ${pet.name} sera supprimée, ainsi que : '
                '${parts.join(', ')}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await controller.delete(pet);
    } on RecordException catch (e) {
      messenger.showSnackBar(
          SnackBar(backgroundColor: AppColors.danger, content: Text(e.message)));
      return false;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Fiche de ${pet.name} supprimée')));
    return true;
  }

  static Future<void> seedDemo(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final count = await _controller(context).seedDemo();
    messenger.showSnackBar(SnackBar(
      content: Text(count == 0
          ? 'Les exemples sont déjà chargés'
          : '$count animaux d\'exemple ajoutés'),
    ));
  }
}
