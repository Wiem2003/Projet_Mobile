import 'package:flutter/foundation.dart';

import '../models/reminder.dart';
import '../models/reminder_exception.dart';
import '../models/reminder_form_model.dart';
import 'reminders_controller.dart';

/// Controller du formulaire : traite la saisie, applique les règles
/// (le titre suit le type, vaccin => annuel) et enregistre via le
/// [RemindersController].
class ReminderFormController {
  /// [preset] : nouveau rappel pré-rempli (ex. rendez-vous proposé quand la
  /// limite de reports est atteinte).
  ReminderFormController(this._reminders, {Reminder? initial, Reminder? preset})
      : model = ReminderFormModel(
          clock: () => _reminders.model.now,
          pets: _reminders.model.pets,
          initial: initial,
          preset: preset,
          defaultPetId: _reminders.model.petFilter,
          defaultDay: _reminders.model.dayFilter,
          conflictCheck: _reminders.model.intervalConflict,
        );

  final RemindersController _reminders;
  final ReminderFormModel model;

  // ----------------------------------------------------------------- Saisie

  void selectType(ReminderType t) {
    // Le titre suit le type tant que l'utilisateur ne l'a pas personnalisé.
    if (!model.titleTouched || model.title.trim() == model.type.defaultTitle) {
      model
        ..title = t.defaultTitle
        ..titleTouched = false;
    }
    model.type = t;
    if (t == ReminderType.vaccination && !model.isEdit) {
      model.repeat = ReminderRepeat.yearly;
    }
    model.changed();
  }

  /// Champs texte : pas de reconstruction à chaque frappe.
  void setTitle(String value) => model
    ..title = value
    ..titleTouched = true;

  void setNotes(String value) => model.notes = value;

  void _update(VoidCallback change) {
    change();
    model
      ..error = null
      ..changed();
  }

  void setPet(int? id) => _update(() => model.petId = id);

  void setDay(DateTime d) =>
      _update(() => model.day = DateTime(d.year, d.month, d.day));

  void setTime(int hour, int minute) => _update(() => model
    ..hour = hour
    ..minute = minute);

  void toggleOffset(AlertOffset o, bool selected) => _update(
      () => selected ? model.offsets.add(o) : model.offsets.remove(o));

  void setRepeat(ReminderRepeat r) => _update(() => model.repeat = r);

  // ---------------------------------------------------------- Enregistrer

  /// Enregistre en base. Renvoie le rappel enregistré, ou `null` si la
  /// validation l'a refusé (`model.error` est alors renseigné).
  Future<Reminder?> save() async {
    model.error = model.validate();
    if (model.error != null) {
      model.changed();
      return null;
    }
    model
      ..saving = true
      ..changed();
    try {
      return await _reminders.save(model.buildReminder());
    } on ReminderException catch (e) {
      model.error = e.message;
      return null;
    } finally {
      model
        ..saving = false
        ..changed();
    }
  }

  void dispose() => model.dispose();
}
