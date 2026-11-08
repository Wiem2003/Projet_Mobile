import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/feeding_controller.dart';
import '../controllers/feeding_form_controller.dart';
import '../core/theme/app_colors.dart';
import '../models/feeding_form_model.dart';
import '../models/feeding_record.dart';
import '../models/validation.dart';
import 'feeding_style.dart';
import 'screens/feeding_form_screen.dart';

/// Actions du module Alimentation et leurs retours visuels.
abstract final class FeedingActions {
  static FeedingController _controller(BuildContext context) =>
      context.read<FeedingController>();

  static Future<void> _guard(
      ScaffoldMessengerState messenger, Future<void> Function() action) async {
    try {
      await action();
    } on RecordException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(e.message),
        ));
    }
  }

  static Future<void> openForm(BuildContext context, {FeedingRecord? record}) {
    final controller = _controller(context);
    return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Provider<FeedingFormController>(
        create: (_) => FeedingFormController(controller, initial: record),
        dispose: (_, c) => c.dispose(),
        child: Builder(
          builder: (context) => ChangeNotifierProvider<FeedingFormModel>.value(
            value: context.read<FeedingFormController>().model,
            child: const FeedingFormScreen(),
          ),
        ),
      ),
    ));
  }

  static Future<bool> delete(BuildContext context, FeedingRecord r) async {
    final controller = _controller(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        title: const Text('Supprimer ce repas ?'),
        content: Text('${r.foodType.label} du ${Fmt.medium(r.date)} '
            '(${Units.grams(r.quantityG)}, ${Units.money(r.price)}) sera '
            'retiré de l\'historique et des calculs.'),
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
    var deleted = false;
    await _guard(messenger, () async {
      await controller.delete(r);
      deleted = true;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('Repas supprimé'),
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () => _guard(
                messenger,
                () => controller.save(FeedingRecord(
                      petId: r.petId,
                      date: r.date,
                      foodType: r.foodType,
                      quantityG: r.quantityG,
                      price: r.price,
                      meals: r.meals,
                      brand: r.brand,
                    ))),
          ),
        ));
    });
    return deleted;
  }

  static Future<void> seedDemo(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_controller(context).model.pets.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Ajoutez d\'abord un animal (Accueil → Mes animaux)')));
      return;
    }
    final count = await _controller(context).seedDemo();
    messenger.showSnackBar(SnackBar(
      content: Text(count == 0
          ? 'Les exemples sont déjà chargés'
          : '$count repas d\'exemple ajoutés'),
    ));
  }
}
