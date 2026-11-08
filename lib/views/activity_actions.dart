import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/activities_controller.dart';
import '../controllers/activity_form_controller.dart';
import '../controllers/walk_tracking_controller.dart';
import '../core/theme/app_colors.dart';
import '../models/activity.dart';
import '../models/activity_form_model.dart';
import '../models/gps/location_source.dart';
import '../models/gps/walk_session_model.dart';
import '../models/validation.dart';
import 'activity_style.dart';
import 'screens/activity_form_screen.dart';
import 'screens/walk_tracking_screen.dart';

/// Actions du module Activités et leurs retours visuels.
abstract final class ActivityActions {
  static ActivitiesController _controller(BuildContext context) =>
      context.read<ActivitiesController>();

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

  static Route<void> _formRoute(ActivitiesController controller,
          {Activity? activity, WalkResult? walk}) =>
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Provider<ActivityFormController>(
          create: (_) =>
              ActivityFormController(controller, initial: activity, walk: walk),
          dispose: (_, c) => c.dispose(),
          child: Builder(
            builder: (context) => ChangeNotifierProvider<ActivityFormModel>.value(
              value: context.read<ActivityFormController>().model,
              child: const ActivityFormScreen(),
            ),
          ),
        ),
      );

  static Future<void> openForm(BuildContext context, {Activity? activity}) =>
      Navigator.of(context)
          .push(_formRoute(_controller(context), activity: activity));

  /// Fin de promenade GPS : remplace l'écran de suivi par le formulaire
  /// prérempli (distance, durée, trajet).
  static Future<void> saveWalk(BuildContext context, WalkResult walk) =>
      Navigator.of(context)
          .pushReplacement(_formRoute(_controller(context), walk: walk));

  /// Ouvre l'écran « Promenade GPS ».
  static Future<void> startWalk(BuildContext context) {
    final source = context.read<LocationSource>();
    final model = _controller(context).model;
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Provider<WalkTrackingController>(
        create: (_) =>
            WalkTrackingController(source: source, clock: () => model.now),
        dispose: (_, c) => c.dispose(),
        child: Builder(
          builder: (context) => ChangeNotifierProvider<WalkSessionModel>.value(
            value: context.read<WalkTrackingController>().model,
            child: const WalkTrackingScreen(),
          ),
        ),
      ),
    ));
  }

  static Future<bool> delete(BuildContext context, Activity a) async {
    final controller = _controller(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        title: const Text('Supprimer cette activité ?'),
        content: Text('${a.type.label} du ${Fmt.dateTime(a.date)} '
            '(${Units.minutes(a.durationMin)}'
            '${a.hasRoute ? ', trajet GPS compris' : ''}) sera supprimée.'),
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
      await controller.delete(a);
      deleted = true;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Activité supprimée')));
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
          : '$count activités d\'exemple ajoutées'),
    ));
  }
}
