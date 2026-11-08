import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/health_booklet_controller.dart';
import '../core/theme/app_colors.dart';
import '../models/health_record.dart';
import '../models/pet.dart';
import '../models/pets_model.dart';

/// Carnet de santé en PDF, avec ou sans synthèse Gemini (fiche animal et
/// menu de l'écran Santé).
abstract final class HealthBookletActions {
  /// Choix (avec / sans Gemini), génération puis partage.
  static Future<void> share(BuildContext context, Pet pet, List<HealthRecord> records) async {
    final controller = context.read<HealthBookletController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);

    var withAi = false;
    if (controller.aiAvailable) {
      final choice = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Carnet de santé de ${pet.name}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
                title: const Text('Avec synthèse Gemini'),
                subtitle: Text("Résumé, points d'attention, conseils et questions pour le "
                    'vétérinaire. Les données de santé de ${pet.name} sont envoyées à Google.'),
                isThreeLine: true,
                onTap: () => Navigator.pop(ctx, true),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.health),
                title: const Text('Carnet simple'),
                subtitle: const Text('Sans IA, préparé sur le téléphone.'),
                onTap: () => Navigator.pop(ctx, false),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (choice == null) return;
      withAi = choice;
    }
    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                  width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(withAi
                    ? 'Gemini rédige la synthèse du carnet de ${pet.name}…'
                    : 'Préparation du carnet de ${pet.name}…'),
              ),
            ],
          ),
        ),
      ),
    );
    final BookletShareResult result;
    try {
      result = await controller.prepareBooklet(pet, records, withAi: withAi);
    } on Exception catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Carnet impossible à préparer : $e')));
      return;
    }
    navigator.pop();
    if (withAi && result.aiError != null) {
      messenger.showSnackBar(SnackBar(
          content: Text('Synthèse Gemini indisponible (${result.aiError}) : '
              'carnet partagé sans elle.')));
    }
    try {
      await controller.share(result);
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Partage impossible : $e')));
    }
  }

  /// Menu de l'écran Santé : l'animal choisi en haut, sinon on le demande.
  static Future<void> shareFromHealth(BuildContext context,
      {required int? selectedPetId, required List<HealthRecord> records}) async {
    final petsModel = context.read<PetsModel>();
    final pets = petsModel.all;
    if (pets.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Ajoutez d'abord un animal.")));
      return;
    }
    Pet? pet = selectedPetId == null ? null : petsModel.byId(selectedPetId);
    pet ??= pets.length == 1
        ? pets.single
        : await showDialog<Pet>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Carnet de quel animal ?'),
              children: [
                for (final p in pets)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, p),
                    child: Text('${p.species.emoji}  ${p.name}',
                        style: const TextStyle(fontSize: 16)),
                  ),
              ],
            ),
          );
    if (pet == null || !context.mounted) return;
    await share(context, pet, records);
  }
}
