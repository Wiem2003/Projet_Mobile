import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/health_controller.dart';
import '../controllers/health_form_controller.dart';
import '../core/theme/app_colors.dart';
import '../models/health_form_model.dart';
import '../models/health_record.dart';
import '../models/validation.dart';
import 'health_style.dart';
import 'screens/health_form_screen.dart';

/// Actions du module Santé et leurs retours visuels.
abstract final class HealthActions {
  static HealthController _controller(BuildContext context) =>
      context.read<HealthController>();

  /// [record] : modification ; [preset] : nouveau dossier pré-rempli.
  static Future<void> openForm(BuildContext context,
      {HealthRecord? record, HealthRecord? preset}) {
    final controller = _controller(context);
    return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Provider<HealthFormController>(
        create: (_) => HealthFormController(controller, initial: record, preset: preset),
        dispose: (_, c) => c.dispose(),
        child: Builder(
          builder: (context) => ChangeNotifierProvider<HealthFormModel>.value(
            value: context.read<HealthFormController>().model,
            child: const HealthFormScreen(),
          ),
        ),
      ),
    ));
  }

  static Future<bool> delete(BuildContext context, HealthRecord r) async {
    final controller = _controller(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        title: const Text('Supprimer ce dossier ?'),
        content: Text('${r.type.label} du ${Fmt.long(r.date)} sera supprimé'
            '${r.nextDue == null ? '' : ', ainsi que le rappel de son échéance'}.'),
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
      await controller.delete(r);
    } on RecordException catch (e) {
      messenger.showSnackBar(
          SnackBar(backgroundColor: AppColors.danger, content: Text(e.message)));
      return false;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Dossier supprimé')));
    return true;
  }

  static Future<void> seedDemo(BuildContext context) async {
    final controller = _controller(context);
    final messenger = ScaffoldMessenger.of(context);
    if (controller.model.pets.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Ajoutez d\'abord un animal (Accueil → Mes animaux)')));
      return;
    }
    final count = await controller.seedDemo();
    messenger.showSnackBar(SnackBar(
      content: Text(count == 0
          ? 'Les exemples sont déjà chargés'
          : '$count dossiers d\'exemple ajoutés — échéances ajoutées aux rappels'),
    ));
  }
}
