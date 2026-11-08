import 'package:flutter/foundation.dart';

import '../core/pets/pet_directory.dart';
import 'reminder.dart';
import 'reminder_planning.dart';
import 'reminder_calculator.dart';
import 'validation.dart';

/// Model du formulaire de création / modification : le rappel en cours de
/// saisie, ses calculs (aperçu des notifications) et sa validation.
///
/// Observé par le formulaire ; modifié uniquement par
/// le `ReminderFormController`.
class ReminderFormModel extends ChangeNotifier {
  ReminderFormModel({
    required this.clock,
    required this.pets,
    this.initial,
    Reminder? preset,
    int? defaultPetId,
    DateTime? defaultDay,
    this.conflictCheck,
  }) {
    // [preset] pré-remplit un nouveau rappel ; [initial] est modifié.
    final r = initial ?? preset;
    final start = r?.dueDate ?? defaultDay ?? now.add(const Duration(days: 1));
    type = r?.type ?? ReminderType.vaccination;
    title = r?.title ?? type.defaultTitle;
    titleTouched = r != null;
    petId = r?.petId ?? defaultPetId;
    day = DateTime(start.year, start.month, start.day);
    hour = r?.dueDate.hour ?? 9;
    minute = r?.dueDate.minute ?? 0;
    offsets = {...(r?.alertOffsets ?? AlertOffset.defaults)};
    repeat = r?.repeat ?? ReminderRepeat.none;
    notes = r?.notes ?? '';
  }

  static const maxTitleLength = 80;

  final DateTime Function() clock;
  final List<PetSummary> pets;

  /// Rappel modifié (null pour une création).
  final Reminder? initial;

  /// Vérifie les délais minimaux entre soins (fourni par le module Rappels).
  final IntervalConflict? Function({
    required int? petId,
    required ReminderType type,
    required DateTime date,
    int? selfId,
  })? conflictCheck;

  /// Soin trop proche d'un autre pour le même animal : avertissement (le
  /// rappel peut quand même être enregistré).
  IntervalConflict? get intervalConflict => conflictCheck?.call(
      petId: petId, type: type, date: dueDate, selfId: initial?.id);

  late ReminderType type;
  late String title;

  /// Vrai dès que l'utilisateur a personnalisé le titre.
  late bool titleTouched;
  late int? petId;
  late DateTime day;
  late int hour;
  late int minute;
  late Set<AlertOffset> offsets;
  late ReminderRepeat repeat;
  late String notes;
  bool saving = false;
  String? error;

  /// Signale aux Views que le formulaire a changé.
  void changed() => notifyListeners();

  // ---------------------------------------------------------------- Calculs

  bool get isEdit => initial != null;
  DateTime get now => clock();

  DateTime get dueDate => DateTime(day.year, day.month, day.day, hour, minute);

  /// Raccourcis de date : Demain, +1 semaine...
  List<(String, DateTime)> get quickDates {
    final n = now;
    return [
      ('Demain', DateTime(n.year, n.month, n.day + 1)),
      ('+1 semaine', DateTime(n.year, n.month, n.day + 7)),
      ('+1 mois', DateTime(n.year, n.month + 1, n.day)),
      ('+3 mois', DateTime(n.year, n.month + 3, n.day)),
      ('+1 an', DateTime(n.year + 1, n.month, n.day)),
    ];
  }

  /// Toutes les notifications (passées barrées dans la View).
  List<({AlertOffset offset, DateTime at})> get alertSchedule =>
      ReminderCalculator.alertSchedule(buildReminder());

  int get pendingAlertCount =>
      ReminderCalculator.pendingAlerts(buildReminder(), now).length;

  DateTime? get nextOccurrence =>
      ReminderCalculator.nextOccurrence(dueDate, repeat);

  // ------------------------------------------------------------- Validation

  /// Validation du titre (T02), réutilisée par le TextFormField.
  static String? validateTitle(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Le titre est obligatoire';
    if (v.length > maxTitleLength) {
      return 'Maximum $maxTitleLength caractères';
    }
    return InputRules.text(v, 'Le titre', max: maxTitleLength);
  }

  static const maxNotesLength = 500;

  static String? validateNotes(String? value) =>
      InputRules.text(value, 'Les notes', max: maxNotesLength);

  /// Message d'erreur, ou null si le rappel peut être enregistré.
  String? validate() {
    final titleError = validateTitle(title) ?? validateNotes(notes);
    if (titleError != null) return titleError;
    final dateChanged = initial?.dueDate != dueDate;
    if (dateChanged && !dueDate.isAfter(now)) {
      return 'La date et l\'heure doivent être dans le futur.';
    }
    return null;
  }

  Reminder buildReminder() {
    final cleanNotes = notes.trim();
    final base = initial;
    if (base == null) {
      return Reminder(
        petId: petId,
        title: title.trim(),
        type: type,
        dueDate: dueDate,
        alertOffsets: offsets.toList(),
        repeat: repeat,
        notes: cleanNotes.isEmpty ? null : cleanNotes,
      );
    }
    return base.copyWith(
      petId: () => petId,
      title: title.trim(),
      type: type,
      dueDate: dueDate,
      alertOffsets: offsets.toList(),
      repeat: repeat,
      notes: () => cleanNotes.isEmpty ? null : cleanNotes,
    );
  }
}
