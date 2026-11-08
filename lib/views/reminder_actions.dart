import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../models/reminder.dart';
import '../models/reminder_exception.dart';
import '../models/reminder_rules.dart';
import '../controllers/reminder_form_controller.dart';
import '../controllers/reminders_controller.dart';
import '../models/reminder_form_model.dart';
import 'reminder_style.dart';
import 'screens/reminder_form_screen.dart';
import 'sheets/postpone_sheet.dart';

/// Actions communes (carte, fiche détail, notification) et leurs retours
/// visuels : SnackBar, confirmation, annulation, erreurs.
abstract final class ReminderActions {
  static RemindersController _controller(BuildContext context) =>
      context.read<RemindersController>();

  /// Exécute [action] et affiche l'erreur métier éventuelle.
  static Future<void> _guard(
      ScaffoldMessengerState messenger, Future<void> Function() action) async {
    try {
      await action();
    } on ReminderException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(e.message),
        ));
    }
  }

  static Future<void> markDone(BuildContext context, Reminder r) async {
    final controller = _controller(context);
    final messenger = ScaffoldMessenger.of(context);
    await _guard(messenger, () async {
      final result = await controller.markDone(r);
      final next = result.next;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(next == null
              ? '« ${r.title} » marqué comme fait ✓'
              : 'Fait ✓ — prochain rappel le ${Fmt.medium(next.dueDate)}'),
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () => _guard(messenger, () => controller.undoDone(result)),
          ),
        ));
    });
  }

  static Future<void> postpone(BuildContext context, Reminder r) async {
    final controller = _controller(context);
    final messenger = ScaffoldMessenger.of(context);
    // Limite de reports atteinte : on propose un rendez-vous à la place.
    if (ReminderRules.needsAppointment(r)) {
      return _proposeAppointment(context, r,
          ReminderRules.postponeError(r, r.dueDate, controller.model.now)!);
    }
    final date = await showPostponeSheet(context, r, now: controller.model.now);
    if (date == null || !context.mounted) return;
    try {
      final saved = await controller.postpone(r, date);
      final left = ReminderRules.remainingPostpones(saved);
      final detail = switch (left) {
        null => 'notifications reprogrammées',
        0 => 'dernier report utilisé',
        1 => 'encore 1 report possible',
        _ => 'encore $left reports possibles',
      };
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Reporté au ${Fmt.dateTime(saved.dueDate)} — $detail'),
        ));
    } on ReminderException catch (e) {
      if (e.isPostponeLimit && context.mounted) {
        return _proposeAppointment(context, r, e.message);
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(e.message),
        ));
    }
  }

  /// Refus du report : explique la règle et propose de prendre rendez-vous.
  static Future<void> _proposeAppointment(
      BuildContext context, Reminder r, String message) async {
    final now = _controller(context).model.now;
    final book = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.event_busy_rounded, color: AppColors.danger),
        title: const Text('Report impossible'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Plus tard')),
          FilledButton.icon(
            icon: const Icon(Icons.event_available_rounded),
            onPressed: () => Navigator.pop(ctx, true),
            label: const Text('Prendre rendez-vous'),
          ),
        ],
      ),
    );
    if (book == true && context.mounted) {
      await openForm(context, preset: ReminderRules.appointmentFor(r, now));
    }
  }

  static Future<bool> delete(BuildContext context, Reminder r) async {
    final controller = _controller(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        title: const Text('Supprimer ce rappel ?'),
        content: Text(
          r.isAutomatic
              ? '« ${r.title} » a été généré depuis : ${r.source.label}. '
                  'Il pourra être recréé si l\'échéance source est modifiée.'
              : '« ${r.title} » et ses notifications seront définitivement supprimés.',
        ),
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
        ..showSnackBar(const SnackBar(content: Text('Rappel supprimé')));
    });
    return deleted;
  }

  static Future<void> reopen(BuildContext context, Reminder r) =>
      _guard(ScaffoldMessenger.of(context), () => _controller(context).reopen(r));

  /// [reminder] : modification ; [preset] : nouveau rappel pré-rempli.
  static Future<void> openForm(BuildContext context,
      {Reminder? reminder, Reminder? preset}) {
    final controller = _controller(context);
    return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Provider<ReminderFormController>(
        create: (_) =>
            ReminderFormController(controller, initial: reminder, preset: preset),
        dispose: (_, c) => c.dispose(),
        child: Builder(
          builder: (context) => ChangeNotifierProvider<ReminderFormModel>.value(
            value: context.read<ReminderFormController>().model,
            child: const ReminderFormScreen(),
          ),
        ),
      ),
    ));
  }
}
